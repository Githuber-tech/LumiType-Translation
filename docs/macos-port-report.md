# LumiType macOS 移植 · 交付报告（2026-11-04）

## 1. 起点：这条移植线之前已经有什么

| 资产 | 位置 | 性质 |
|---|---|---|
| 功能基线规格（12 节 / 44 字段 / 16 错误码 / 8 项托盘 / 4 页首选项） | `docs/feature-inventory.md` | 验收契约 |
| 可行性与技术选型（Swift 原生重写，macOS 13+，不上架 App Store） | `docs/feasibility-assessment.md` | 决策记录 |
| Windows 源码 V6.2.0（12 个 .cs，10 741 行） | `src/` | 行为与默认值的唯一事实来源 |
| 业务核心 Swift 版（阶段 1） | `macos/Sources/LumiTypeCore` | 配置 / 三引擎 / LRU / i18n / 语言方向 / 更新日志 |
| 回归断言（81 项） | `macos/Sources/verify` | 不依赖 Xcode 的自检 |

本次工作是在上述基础上继续：**阶段 2 平台层 + 阶段 3 界面层 + 阶段 4 打包**，把它变成可双击运行的
macOS 应用，而不是停留在库 + 命令行。

## 2. 本次交付

```
macos/
├── Sources/LumiTypeApp/            22 个文件、约 4 700 行 Swift（全部新增）
├── build-app.sh                    通用二进制 + .app + icns + 签名 + zip + dmg
├── README.md                       重写：构建、权限、架构、差异、自检方法
├── preview/                        9 张自检截图（卡片 / 真实窗口 / 四个分页）
└── dist/
    ├── LumiType.app                可直接运行（x86_64 + arm64）
    ├── LumiType-2.0.0-macOS.zip
    └── LumiType-2.0.0-macOS.dmg    拖拽安装
```

应用形态：菜单栏常驻（`LSUIElement`，无 Dock 图标）、`⌥Y` 唤出浮层、
`Enter` 把译文送回原应用、四页首选项、反馈存档、更新检查。

## 3. 关键取舍（以及为什么）

| 问题 | 选择的方案 | 理由 |
|---|---|---|
| 全局键鼠钩子（`SetWindowsHookEx`） | **不移植** | 浮层本身是 key window，Esc/Enter/Tab 由 `NSTextView` 直接收到；没有钩子反而不会出现原版「钩子吞掉别的软件 Esc」的问题 |
| 逐像素透明 + 抓屏毛玻璃（`UpdateLayeredWindow` + `PrintWindow`） | **`NSPanel` + `NSVisualEffectView(.hudWindow/.popover)`** | 真·系统玻璃，零屏幕录制授权，滚动/切换桌面都跟随；放弃「透出背后窗口的模糊像素」这一点点差异 |
| 光标定位（`GetGUIThreadInfo`） | 鼠标位置 + `OffsetX/OffsetY` | 核对 `src/Overlay.cs` 后确认原版就是 `Cursor.Position`，不是插入符矩形；AX 取插入符在微信/Chromium 上并不可靠 |
| 模拟 Ctrl+V（`keybd_event`） | `NSRunningApplication.activate` + `CGEvent` ⌘V | 需要辅助功能授权；未授权时**降级为剪贴板 + 界面提示**，不静默失败 |
| 开机启动（注册表 Run） | `SMAppService`（13+），失败回退 LaunchAgent | 官方 API，用户在「登录项」里可见可控 |
| 托盘（`Shell_NotifyIcon`） | `NSStatusItem` + Core Graphics 动态图标 | 与 exe 图标同一套「青紫渐变 + 译」 |
| 版本号 | macOS 版 **2.0.0**，功能基线 Windows **6.2.0** | 两个版本概念分开：`Product.version` 管应用自身版本与更新比较，`parityBaseline` 记录对齐目标；更新日志首条为 macOS 2.0.0，其后是继承的 Windows 历史 |

## 4. 行为对齐里几个容易被忽略、但确实做了的点

1. **DeepL Key 回退**：`DeeplKey` 为空时回退旧 `ApiKey`（v6.1.6 的 403 事故）。
2. **自动方向**：输入已是目标语言时翻回输入侧；`PinSource/PinTarget` 可锁定；CJK 才给 `source_lang`，
   拉丁语系交给服务端识别（照 `Prompt.DeepLSourceCode`）。
3. **DeepL `context` 字段**：原版用它稳定商务口吻，且不计费 —— 已一并带上。
4. **V6.2.0 出发时机**：句末标点 → 220 ms 即发；没有句末标点 → 等 2.5 s，避免半句碎片。
5. **V6.2.0 长连接复用 + 启动预热**：`URLSession` 按代理配置复用，启动时 `GET /v2/usage` 预建连接
   （不产生翻译计费）。
6. **V5.9.0 提交契约**：`Enter` 只在「当前译文就是这段输入的译文」时才粘；否则先整段翻译再插，
   绝不把原文当译文粘出去。
7. **输入法**：`NSTextView` 原生 IME；`hasMarkedText()` 时回车/Esc 交给输入法，不会被当成提交/关闭。
8. **吸附**：上/下 44 px 热区、脉冲高亮、松手吸附、宽度跟随（100 ms 节流）、目标窗口关闭 200 ms 内退出。
9. **单实例**：`flock`；`--restart-after <pid>` 先等旧进程退出再抢锁与热键，避免重启后热键注册失败。

## 5. 验证证据

| 项目 | 命令 | 结果 |
|---|---|---|
| 核心回归 | `swift run verify` | **81 项断言全通过**（配置 / 版本 / LRU / 引擎 / 端到端 / 文案 / 更新日志 / 语言方向） |
| 卡片视觉 | `LumiType --preview ...` | 三皮肤 × 完成/流式/等待/错误/吸附，见 `preview/card-*.png` |
| 真实窗口 | `LumiType --demo "..." --demo-shot png` | 见 `preview/live-window.png`、`preview/live-translation.png`（含玻璃、输入框、光标、思考点、延迟徽章） |
| 首选项四页 | `LumiType --prefs-shot ... --prefs-tab 0..3` | 见 `preview/prefs-*.png` |
| 端到端翻译 | 本地桩 DeepL + `--translate` / GUI `--demo` | 请求 → 解析 → 缓存 → 状态行（4 ms · 15 字）全部走通 |
| 打包 | `bash build-app.sh release` | `.app` 为 `x86_64 arm64` 通用二进制，ad-hoc 签名校验通过，zip + dmg 产出 |
| 打包后运行 | `dist/LumiType.app/Contents/MacOS/LumiType --demo ...` | 正常启停，日志写入 `~/Library/Application Support/LumiType/logs/` |

## 6. 如实说明的限制

1. **未公证**：`build-app.sh` 默认 ad-hoc 签名，本机可运行；外发需 Developer ID + `notarytool`
   （证书不在本机，脚本已留 `LUMITYPE_SIGN_IDENTITY` 入口）。
2. **更新器未做真实发版回归**：清单解析、版本比较、SHA256 校验、替换 `.app` 的代码路径齐备，
   但没有一次真实「旧版 → 新版」的线上包验证。
3. **吸附白名单是映射而非等价**：Windows 按进程名，macOS 按 bundle id 映射 21 个应用；
   未在名单内的应用拖过去不会吸附。
4. **「以管理员身份运行」不适用**：控件保留但禁用，状态栏的「权限」改为显示辅助功能授权状态。
5. **`ShowLatency` 仍是死字段**：原版 V6.2.0 同样只存在于配置/模型、不参与布局，此处保持一致。
6. **浮层内没有语言下拉菜单**：原版 V6.0 起点胶囊可临时选语言；当前用 ⇄ 对换 + 首选项配置覆盖主路径。

## 7. 下一步建议（按性价比排序）

1. 用真实 DeepL Key 跑 20 条业务句，校对卡片排版与译文口吻（`context` 是否够「商务」）。
2. 在微信 / 飞书 / 钉钉 / Chrome 上各测 20 次 Enter 插入，确认辅助功能授权与焦点归还稳定。
3. 补 Developer ID + 公证流水线，做一次真实发版验证更新器。
4. 若需要浮层内切语言，加 `NSPopover` 语言菜单（`OverlayView` 已有胶囊命中区，改动面很小）。
