# LumiType for macOS

`LumiType.exe`（V6.2.0 源码基线）的 macOS 原生重写，**macOS 版自身版本 2.0.0**。**不是**兼容层、不是虚拟机跑 exe：
界面用 AppKit + Core Graphics 重绘，平台能力换成 Carbon / CGEvent / NSVisualEffectView，
业务核心（三个翻译引擎、LRU 缓存、语言方向、配置体系、中英文案、更新日志）与 Windows 版逐条对齐。

当前状态：**可运行的完整应用**（菜单栏驻留 + 浮层翻译 + 首选项 4 页 + 反馈 + 更新 + CLI）。
版本口径：应用版本 `2.0.0`（`Product.version`），功能基线对齐 Windows `6.2.0` —— 更新日志里
`2.0.0` 条目排在最前，其后是继承的 Windows 历史。
核心回归 81 项断言全部通过。

---

## 1. 构建与运行

```bash
cd macos

./build.sh                 # 调试构建（.build 放在 ~/Library/Caches/LumiTypeBuild，避免 OneDrive 同步冲突）
swift run verify           # 81 项核心断言

bash build-app.sh          # Release 构建 + 组装 LumiType.app + icns + ad-hoc 签名 + zip
open dist/LumiType.app
```

产物：

```
dist/LumiType.app                     可直接双击运行（菜单栏出现「译」图标，不占 Dock）
dist/LumiType-2.0.0-macOS.zip         分发包
```

首次运行会在 `~/Library/Application Support/LumiType/` 生成：

```
settings.json          44 个字段，键名与 Windows 版完全一致（可直接拷过来用）
transcache.json        LRU 译文缓存
logs/lumitype-*.log    运行日志（单文件滚动 .1）
feedback/FB-*/         反馈本地存档
```

## 2. 首次使用：填 Key

菜单栏图标 → 首选项 → 翻译引擎 · API → 粘贴 Key → 点「应用」。
DeepL 免费版 Key 以 `:fx` 结尾。三个引擎各自独立保存，`ApiKey` 旧字段仍作为 DeepL 的回退
（v6.1.6 修的 403 事故）。

**辅助功能授权**：把译文自动插入别的应用需要「系统设置 → 隐私与安全性 → 辅助功能」勾选
LumiType（未授权时译文仍会进剪贴板，界面上会提示按 ⌘V）。全局热键本身不需要授权。

## 3. 操作

| 操作 | 结果 |
|---|---|
| `⌥Y`（Alt+Y） | 在光标旁唤出并激活浮层（每次新建独立实例） |
| `⌃⌥Y`（Ctrl+Alt+Y） | 翻译剪贴板内容 |
| 浮层内 `Enter` | 译文送回唤出前的应用光标处；已吸附时插入被吸附窗口 |
| `⌃Enter` | 输出原文 |
| `⇧Enter` | 输入框内换行 |
| `Tab` | 在已配置 Key 的引擎间循环 |
| `Esc` | 关闭当前浮层 |
| 拖到聊天窗口上/下边缘 44px | 出现脉冲高亮，松手吸附；吸附后宽度跟随窗口，窗口关闭浮层自动退出 |
| 右上 ✕ / 记事本 | 关闭浮层 / 打开草稿本 |

## 4. 代码结构

```
macos/
├── Package.swift
├── build.sh                调试构建（自定义 scratch 路径）
├── build-app.sh            .app 打包（Info.plist / icns / 签名 / zip）
├── Sources/
│   ├── LumiTypeCore/       与平台无关的业务核心（可单测、被 CLI 与 App 共用）
│   │   ├── Config.swift            44 字段 + 容错解析 + 损坏隔离 + Key 回退
│   │   ├── Models.swift            语言表 / 引擎枚举 / 16 条错误码
│   │   ├── Engines.swift           DeepL / Google / LLM + LRU 缓存 + 长连接复用
│   │   ├── LanguageResolver.swift  脚本识别、自动方向、DeepL/Google source 代码
│   │   ├── LruCache.swift          持久化 LRU（transcache.json）
│   │   ├── I18n.swift              中英词表（键值与 exe 逐条一致 + macOS 补充项）
│   │   ├── Changelog.swift         + ChangelogData.swift（70 条版本记录）
│   │   ├── Prompt.swift / Version.swift
│   ├── LumiTypeApp/        AppKit 应用
│   │   ├── main.swift / AppCLI.swift      CLI 与 GUI 分流
│   │   ├── AppDelegate.swift              生命周期、单实例、托盘、更新、权限引导
│   │   ├── StatusMenu.swift               菜单栏 8 项
│   │   ├── OverlayController.swift        浮层实例：状态机、防抖、提交、吸附跟随
│   │   ├── OverlayView.swift              卡片绘制（照抄 CardRenderer 的绘制顺序与色值）
│   │   ├── CardModel.swift / Theme.swift / Typo.swift   布局度量、24 色 × 3 皮肤、Core Text 排版
│   │   ├── InputTextView.swift            浮层输入框（中文输入法可用）
│   │   ├── Hotkeys.swift                  全局热键（Carbon RegisterEventHotKey）
│   │   ├── SnapMonitor.swift              吸附目标发现与跟随（CGWindowList）
│   │   ├── PasteService.swift             激活原应用 + 合成 ⌘V + 剪贴板还原
│   │   ├── PreferencesWindow.swift        四页首选项
│   │   ├── Feedback.swift                 写反馈 + 4 列历史 + 本地存档 + multipart
│   │   ├── Updater.swift                  latest.json + SHA256 + 替换 .app
│   │   ├── AutoStart.swift                SMAppService（13+）/ LaunchAgent 回退
│   │   ├── PreviewRenderer.swift          --preview 离屏渲染（自检用）
│   │   └── Log.swift / Snapshot.swift / IconArt.swift
│   └── lumitype/, verify/, probe/         纯 CLI、回归断言、光标探测工具
└── preview/                 离屏渲染与真实窗口截图（自检产物）
```

## 5. Windows → macOS 能力映射

| Windows | macOS 实现 | 备注 |
|---|---|---|
| `RegisterHotKey` | Carbon `RegisterEventHotKey` | 不需要额外授权 |
| `SetWindowsHookEx` 键鼠钩子 | **不移植** | 浮层是 key window，Esc/Enter/Tab 由 NSTextView 直接处理，不需要全局钩子 |
| `GetGUIThreadInfo` 取插入符 | 用鼠标位置 + `OffsetX/OffsetY`（与原版 `Cursor.Position` 一致） | 原版其实就是贴着鼠标出现，不是 AX 插入符 |
| `UpdateLayeredWindow` 逐像素透明 | `NSPanel(borderless)` + `NSVisualEffectView(.hudWindow)` + Core Graphics 绘制 | 真·系统毛玻璃，且**不需要屏幕录制授权** |
| 抓目标窗口做磨砂底图 | 不抓屏 | 用 vibrancy 代替，避免权限与性能代价 |
| `SetForegroundWindow` + `Ctrl+V` | `NSRunningApplication.activate` + `CGEvent` ⌘V | 需辅助功能授权；未授权降级为剪贴板 |
| `EnumWindows` 吸附目标 | `CGWindowListCopyWindowInfo` + bundle id 白名单 | 只读窗口框，无需授权 |
| 注册表 Run 键 | `SMAppService.mainAgent`（13+），回退 LaunchAgent plist | 首选项 / 托盘均可切换 |
| `Shell_NotifyIcon` | `NSStatusItem` + 动态绘制图标 | 无 Dock 图标（`LSUIElement`） |
| GDI+ 全自绘 | Core Graphics + Core Text（灰度抗锯齿） | 圆角/渐变/8 层外发光/顶部高光逐条照搬 |
| DWM 颜色化色 | `NSColor.controlAccentColor` | 「主题色」皮肤跟随系统强调色 |

## 6. 与原版的已知差异（有意为之）

1. **没有全局键盘钩子**：macOS 上浮层拿到焦点时按键天然只进浮层，不需要钩子；反而避免了
   原版「钩子越权吞掉别的软件的 Esc」那类问题。
2. **毛玻璃用系统材质**，不抓屏。视觉更接近 macOS 原生玻璃，代价是无法做到「透出背后窗口的
   模糊像素」——原版那套 `GrabScreenBackdrop` 需要屏幕录制授权，收益不抵成本。
3. **「以管理员身份运行」不适用**：该控件保留但禁用，同一状态栏位改为显示「辅助功能」授权状态。
4. **`ShowLatency` 仍是死字段**：原版 V6.2.0 里它同样只存在于配置与模型、不参与布局，此处保持一致。
5. **吸附白名单按 bundle id**：原版 18 个 Windows 进程名 → 21 个 macOS 应用（微信 / WhatsApp /
   QQ / 飞书 / Lark / 钉钉 / 备忘录 / Safari / Mailbird / Chrome / Edge / Brave / Opera / Vivaldi /
   VS Code / Slack / Discord / Notion / Teams / Spotify / Figma）。
6. **`--apply-update` 不单独执行**：更新由应用内更新器接管（下载 → SHA256 校验 → 替换 .app → 重启）。

## 7. 自检方式（不需要屏幕录制权限）

```bash
B=.build/debug/LumiTypeMac     # 或 ~/Library/Caches/LumiTypeBuild/debug/LumiTypeMac

# 1) 卡片离屏渲染：三种皮肤 × 多种状态，直接出 PNG
$B --preview preview/card.png --theme glass-dark --state done --scale 2
$B --preview preview/card_light.png --theme paper-light --state done --scale 2
$B --preview preview/card_pinned.png --theme accent-glass --state streaming --scale 2 --pinned

# 2) 真实窗口（含 vibrancy、输入框、输入法宿主）渲染成 PNG 后退出
$B --demo "你好，世界。这是流式翻译测试。" --demo-shot preview/live.png

# 3) 首选项四个分页
$B --prefs-shot preview/prefs.png --prefs-tab 2

# 4) 端到端翻译（本地桩服务器，避免消耗真实额度）
python3 - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        out = {"translations":[{"detected_source_language":"ZH","text":"[MOCK] "+body["text"][0]}]}
        b = json.dumps(out).encode()
        self.send_response(200); self.send_header('Content-Type','application/json')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
HTTPServer(('127.0.0.1', 18099), H).serve_forever()
PY
$B --translate "你好，世界" --api-key test:fx --base-url http://127.0.0.1:18099/v2/ --target English
```

## 8. CLI（与 Windows 版参数对齐）

```
LumiType                                 启动菜单栏应用
LumiType --translate <text> [--target LANG] [--api-key KEY] [--base-url URL] [--no-stream]
LumiType --version | --bump <major|minor|patch> [from] | --validate-version <v>
LumiType --config                        打印生效配置
LumiType --prefs                         启动并打开首选项
LumiType --make-icon <out.png> [size]    生成应用图标
LumiType --preview <out.png> [--theme T] [--state S] [--scale N] [--pinned] [--empty]
LumiType --help | -h | /?
```

开发期附加：`--demo "<text>"`、`--demo-shot <png>`、`--prefs-shot <png> [--prefs-tab N]`、
`--restart-after <pid>`（重启时等旧进程退出再抢锁与热键）。

## 9. 分发

不上架 App Store（全局热键、跨应用插入、读取窗口列表三项都踩审核红线）。走直接分发：

```bash
LUMITYPE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash build-app.sh release
# 然后 notarytool submit + stapler（需要开发者账号；未配置时脚本用 ad-hoc 签名，本机可运行）
```

## 10. 后续可做

- Developer ID 公证流水线（需要证书，属于发布环节）
- 吸附目标「每应用记忆上次策略」（原版对 Mailbird 做过特例）
- 浮层内语言菜单（点胶囊临时切语言，当前用 ⇄ 对换 + 首选项配置）
- 更新器的「下载 → 校验 → 原子替换」在真实发布包上的回归（需要一次真实发版）
