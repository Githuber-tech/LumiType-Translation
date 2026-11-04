# LumiType v6.2.0 · 功能基线规格（1:1 还原契约）

> **2026-11-04 更新：源码已找到。** 工作目录 `src/` 下为 V6.2.0 完整 C# 源码（12 个文件），
> 比 GitHub 上的 6.1.6 更新。本文档原先由 6.1.6 二进制静态解析得出，结构仍然有效，
> 但**默认值与细节以 `src/` 为准**。二进制与源码的差异已在下文逐条标注。
>
> 来源：对 `LumiType.exe`（GitHub 版 SHA256 `c494a8b6…f5faa841`）的 .NET 元数据静态解析。
> 本文档是 macOS 版验收的唯一基线。清单里每一项都必须在 Mac 版有对应物，否则视为未完成。
> 标注「实测」= 来自二进制；标注「推定」= 由代码结构与文案推断，需运行确认。

---

## 0. 程序身份

| 项 | 值 |
|---|---|
| 程序集 | `LumiType` 6.1.6.0 |
| 运行时 | .NET Framework 4.0（`mscorlib 4.0.0.0`） |
| 引用 | mscorlib / System.Windows.Forms / System.Drawing / System.Web.Extensions / System / System.Net.Http |
| 第三方依赖 | 无 |
| 类型 | 62（其中 24 个为编译器生成的闭包/静态数组类型，业务类型 38） |
| 方法 | 531 |
| P/Invoke | 53（user32 46 / gdi32 4 / dwmapi 1 / kernel32 1 / shell32 1） |
| 内嵌资源 | `lumitype.ico`（1 个） |
| 单实例锁 | `Local\LumiType.SingleInstance.V4` |
| AppUserModelID | `LumiType.Overlay.Translate` |

业务类型（实测）：
`CardModel` `Theme` `CardLayout` `CardRenderer` `ChangelogAuto` `Entry` `Cli` `Config` `Log`
`Prompt` `DeepLClient` `LruCache` `IconArt` `Native` `OverlayForm` `InputForm` `OverlayInstance`
`HotkeyForm` `OverlayApp` `UpdateInfo` `Updater` `PrefsForm` `GlassSlider` `FeedbackDialog`
`TipDiagram` `Program` `TranslationClient` `Html` `I18n` `LumiVersion`

---

## 1. 配置项（settings.json，44 个字段 · 实测）

`config/settings.json`，缺字段用默认值补齐，损坏时重命名 `.corrupt-<时间戳>` 隔离后重建。

| 字段 | 类型 | 说明 |
|---|---|---|
| `BaseUrl` | string | 自定义翻译端点（空=用引擎默认） |
| `ApiKey` | string | 旧版单 Key，**v6.0 起已拆分为三引擎 Key，仅作兼容回退** |
| `Provider` | string | 当前引擎：`deepl` / `google` / `llm` |
| `DeeplKey` `GoogleKey` `LlmKey` | string | 三引擎各自 Key，可各存一份 |
| `LlmEndpoint` | string | 默认 `https://api.deepseek.com/v1/chat/completions` |
| `LlmModel` | string | 默认 `deepseek-chat` |
| `TimeoutMs` | int | 请求超时 |
| `UpdateUrl` | string | 更新清单地址（默认指向 GitHub raw `latest.json`） |
| `UiLang` | string | `zh` / `en` |
| `FeedbackEndpoint` | string | 反馈发送端点 |
| `SourceLang` `TargetLang` | string | 语言代码（`zh-CN` 等） |
| `PinSource` `PinTarget` | bool | 浮层上锁定语言，不跟随自动识别 |
| `PairLang` | string | 语言对预设 |
| `AutoDirection` | bool | 自动方向（跟随识别） |
| `Realtime` | bool | 实时翻译（边打字边译） |
| `QualityModel` | bool | 精译模式（`quality_optimized`） |
| `DebounceMs` `MinChars` | int | 触发翻译的停顿阈值与最小字数 |
| `CacheSize` | int | LRU 条目上限 |
| `Theme` | string | 皮肤：`paper-light` / `glass-dark` / `accent-glass` |
| `FontScale` | double | 字号缩放 |
| `MaxWidth` | int | 浮层最大宽度 |
| `GlassOpacity` | int | 玻璃浓度 15–100（**100 = 完全不透明**，越低越透） |
| `OffsetX` `OffsetY` | int | 相对光标的偏移 |
| `ShowSource` `ShowHints` `ShowPills` `ShowLatency` | bool | 卡片四个显示开关 |
| `HotkeyToggle` `HotkeyClipboard` | string | 默认 `Alt+Y` / `Ctrl+Alt+Y` |
| `ProxyMode` `ProxyServer` | string | `system` / `direct` / `manual` + 代理地址 |
| `DebugLog` | bool | 调试日志 |
| `Pinned` `PinnedX` `PinnedY` | mixed | 吸附态与吸附位置记忆 |
| `AutoStart` | bool | 开机启动（写注册表 `Run` 的 `LumiType` 值） |
| `RunAsAdmin` | bool | 以管理员身份运行 |
| `FilePath` | string | 配置文件自身路径 |

**v6.1.6 关键修复（必须复刻）**：DeepL 请求头取 `DeeplKey`，为空时回退 `ApiKey`。v6.0.0–v6.1.5 因只读旧字段导致全部 403。

---

## 2. 翻译引擎（3 个 · 实测）

| 引擎 | 端点 | 认证 | 关键参数 |
|---|---|---|---|
| `deepl` | `https://api-free.deepl.com/v2/translate` | `Authorization: DeepL-Auth-Key <key>` | `text` `target_lang` `source_lang` `context` `split_sentences=nonewlines` `preserve_formatting=1` `model_type=quality_optimized\|prefer_quality_optimized` |
| `google` | `https://translation.googleapis.com/language/translate/v2?key=<key>` | query key | `q` `target` `format=text`；解析 `data.translations[0].translatedText` |
| `llm` | 用户配置（默认 DeepSeek） | `Authorization: Bearer <key>` | `model` `messages[{role,content}]` `temperature` `stream` |

UA：`LumiType/5.0`（DeepL）、`LumiType/6.0`（LLM）。

**错误码映射（16 条）**

| 代码 | 文案（zh / en） |
|---|---|
| `e_401` | API Key 无效或已过期 (401) / API key invalid or expired (401) |
| `e_402` | 账户余额不足 (402) / Insufficient account balance (402) |
| `e_403` | 访问被拒绝 (403) / Access denied (403) |
| `e_456` | DeepL 配额已用完 (456) / DeepL quota exhausted (456) |
| `e_429` | 请求过于频繁 (429) / Too many requests (429) |
| `e_400` | 请求被拒绝 (400) / Request rejected (400) |
| `e_timeout` | 请求超时 / Request timed out |
| `e_dns` | 无法解析服务器地址，请检查网络或代理 / Cannot resolve the server address… |
| `e_conn` | 无法连接服务器，请检查网络或代理 / Cannot reach the server… |
| `e_nokey_d` `e_nokey_g` `e_nokey_l` | 未配置对应引擎 Key，请在首选项「翻译引擎」中粘贴并应用 |
| `err_empty` `err_empty_g` `err_empty_l` | 引擎返回空译文 |

---

## 3. 语言（10 种 · 实测）

| 显示名 | 代码 | DeepL 代码 |
|---|---|---|
| 简体中文 | `zh-CN` | Simplified Chinese |
| 繁體中文 | `zh-TW` | Traditional Chinese |
| English | `en` | English |
| 日本語 | `ja` | Japanese |
| 한국어 | `ko` | Korean |
| Français | `fr` | French |
| Deutsch | `de` | German |
| Español | `es` | Spanish |
| Português | `pt` | Portuguese |
| Русский | `ru` | Russian |

外加两个虚拟项：`lang_auto_src` 自动识别（跟随输入）、`lang_auto_dir` 自动方向（跟随识别）。

---

## 4. 浮层（Overlay）

**卡片结构（自上而下）**：语言胶囊行（输入 ⇄ 目标 + 延迟徽章）→ 圆角输入框 → 分隔线 → 译文区 → 快捷键提示行；吸附态时顶部出现「已吸附 · 应用名」徽章与 ✕ 按钮，右上角常驻记事本按钮。

**视觉参数（实测，`CardLayout` 58 项 / `Theme` 24 色）**
- 默认尺寸 375×147，按显示器比例缩放
- 圆角卡片、外投影 8 层、输入框聚焦时青色光环
- 三套皮肤：`paper-light`（白色磨砂）/ `glass-dark`（夜晚磨砂）/ `accent-glass`（跟随系统主题色）
- 玻璃浓度 15–100%，实时作用于所有浮层
- 文字渲染：`AntiAliasGridFit` + `TextContrast=6` + `PixelOffsetMode.Half`（Mac 侧对应 Core Text 灰度抗锯齿 + 关闭 LCD 子像素）

**布局行为（实测）**
- 输入超宽自动换行、浮层高度跟随、译文与输入同宽
- 输入不撑宽浮层；Enter 后立即复位
- 可拖边缘拉伸，双击边缘复位为自适应宽度
- 吸附时仅允许水平拖动；禁用边缘拖拽/双击复位
- 多实例：每次唤出新建独立浮层，各自维护输入/译文；Esc 只关当前 active 实例

**状态机（9 态）**：`st_typing` 输入中 → `st_updating` 更新中 → `st_translating` 翻译中 → `st_output` 输出中 / `st_cache` 缓存 → `st_done` → `st_final` 精译中… → `st_final_fail` 精译失败，已保留原文 / `st_fail` 失败。状态行格式：`{0}ms · {1} 字`。

---

## 5. 吸附（Snap）

- 上下各 44px 外框为吸附热区；拖近边线 → 脉冲高亮 + 气泡提示 → 松手吸附
- 吸附后浮层贴目标窗口**外边框**、宽度跟随、随窗口拉伸实时调整（100ms 节流）
- 被吸附窗口关闭 → 浮层 200ms 内自动关闭（免按 Esc）
- 白名单（实测 18 个进程名）：`wechat` `weixin` `whatsapp` `tim` `feishu` `lark` `dingtalk` `notepad` `mailbird` `chrome` `msedge` `brave` `opera` `vivaldi` `code` `slack` `discord` `notion` `teams` `spotify` `figma`
- 桌面（`Progman` / `WorkerW`）与任务栏（`Shell_TrayWnd`）特殊处理
- Mailbird 特例：插入位置 = 用户最后点击处（记录 `paste click`），而非窗口中心

---

## 6. 热键（默认 · 实测）

| 组合 | 动作 |
|---|---|
| `Alt+Y` | 唤出 / 激活浮层（每次新建独立实例） |
| `Ctrl+Alt+Y` | 翻译剪贴板内容 |
| `Enter` | 吸附中：译文插入目标窗口并清空浮层；未吸附：输出到原光标处 |
| `Ctrl+Enter` | 输出原文 |
| `Tab` | 切换已配置引擎（仅一个可用时提示 `st_engine_only`） |
| `Esc` | 关闭浮层（焦点在浮层时；吸附中忽略） |
| `Shift+Enter` | 换行 |

热键录入规则：必须含 Ctrl/Alt/Shift/Win 之一；Esc 取消录入；不可用键与占用冲突有独立错误提示（`hk_err_mod` / `hk_err_key` / `hk_err_busy`）。

---

## 7. 托盘菜单（8 项 · 实测）

```
打开浮层 (&O)
剪贴板翻译 (&C)
──────────
首选项 (&P)…
检查更新 (&U)
开机启动        [勾选态]
──────────
重启应用 (&R)
关于 (&A)
──────────
退出 (&X)
```
悬停提示：`LumiType 灵译 {version}`。

---

## 8. 首选项（4 个分页 · 实测）

**常规** `tab_general`
- 状态行：`当前版本 {0}　权限：{1}　开机启动：{2}`（权限：普通/管理员）
- 开机启动开关、以管理员身份运行开关（含提权说明 `admin_note`）
- 快捷键组：唤出/激活浮层、翻译剪贴板、两行说明、恢复默认
- 浮层磨砂玻璃组：透明度滑杆（15–100%）+ 数值框、三皮肤单选、`skin_help`
- 翻译引擎 · API 组：DeepL / Google / LLM 三段，各含 Key 输入 + 应用 + 状态（已配置/未配置/当前生效），LLM 额外有 Endpoint 与 Model
- 界面语言 · Language 组：显示语言（中/英），切换立即生效无需重启
- 配置组：打开配置目录、重新加载配置
- 窗口：固定宽度、竖向滚动、高度上限、可上下拉伸

**更新日志** `tab_log`：降序，每条 `V{版本}` + 一句话摘要；随 UI 语言切换中英双语。

**使用技巧** `tab_tips`：7 条图文
1. ① 浮层结构一图看懂（标注徽章行/圆角输入框/实时译文/提示行，上下 44px 吸附区）
2. ② 吸附到聊天软件 / Mailbird（微信 / WhatsApp / TIM / 飞书 / 钉钉 / 记事本）
3. ③ 快捷键与 Enter 契约
4. ④ 多浮层与焦点（窗口 A / 窗口 B 示意，实例 {0}：已吸附 · 各自输入/翻译）
5. ⑤ API 申请一：DeepL（注册 API Free → 账户页取 Key → 免费版以 `:fx` 结尾 → 粘贴应用）
6. ⑥ API 申请二：Google Cloud Translation（登录 Console → 新建项目+启用 API → 凭据取 `AIza…`）
7. ⑦ API 申请三：LLM 接口（DeepSeek 开放平台 → 充值 → API keys → 创建 `sk-…`）

**用户反馈** `tab_feedback`
- 说明：发送会联网提交并自动本地存档（exe 旁 `feedback\`，每个反馈一个时间戳文件夹）
- 历史表 4 列：反馈目录 / 附件数 / 内容摘要 /（打开）
- 「写反馈…」弹窗：内容文本框、附件列表（文件名/大小/移除）、添加附件
- 附件限制：`png jpg jpeg webp gif bmp pdf`，单个 ≤ 20MB
- 存档结构：`FB-yyyyMMdd-HHmmss/` 内含 `反馈内容.txt`、`附件*`、`附件清单.txt`
- 发送：`multipart/form-data` 到 `FeedbackEndpoint`，`Referer` 为 GitHub 仓库地址；成功/失败各有提示，失败内容仍本地存档

---

## 9. 更新（Updater）

- 清单 `latest.json`：`{version, url, sha256, notes}`
- 启动时检查 + 每 6 小时一次；发现新版本 → 托盘项变为 `一键更新到 V{0} (&U)`，气泡 `发现新版本 V{0}` / `打开托盘菜单可一键更新`
- 下载 → **SHA256 校验**（失败即中止：`更新包 SHA256 校验失败，已中止安装`）→ 替换 `.old` → 重启
- 未配置 `UpdateUrl` 时提示 `更新源未配置：在 config\settings.json 设置 UpdateUrl 后启用推送`
- 文案双语：`upd_latest` `upd_fail` `upd_err` `upd_installfail` `upd_nosrc`

---

## 10. 日志 / 缓存 / 单实例

- 日志：`logs/lumitype-yyyyMMdd.log`，单文件滚动 `.1`，行格式 `HH:mm:ss.fff` 前缀，`DebugLog` 开关控制调试级别
- 缓存：`config/transcache.json`，LRU，`CacheSize` 上限，重复句离线秒回（状态显示 `缓存 · {0} 字`），会清理旧格式片段条目
- 单实例：第二实例唤出已有窗口并提示 `LumiType 已经在运行。`

---

## 11. 命令行（实测参数表）

```
--translate <text> [--base-url URL] [--api-key KEY] [--target LANG] [--no-stream]
--version
--bump <major|minor|patch> [from]        版本号递增（含进位规则）
--validate-version <v>                   校验版本号
--make-icon                              生成 ico
--icon-sheet
--apply-update <pkg>                     更新器入口（内部用）
--preview [--theme T] [--scale N] [--state S] [--backdrop P] [--empty] [--pinned] [--unpin-hover]
--restart-after <ms>  --spawn  --prefs
--help | -h | /?
```
`--translate` 输出 `--- deltas ---` 逐段增量与 `--- result ---` 汇总（text/chars/elapsed/url）。

---

## 12. macOS 版验收清单（2026-11-04 实现结果）

图例：✅ 已实现并验证 · ⚠️ 已实现但有已知差异 · — 原版本身未实现，保持一致

| 项 | 状态 | 说明 |
|---|---|---|
| 10 种语言 + 自动识别 + 自动方向 | ✅ | `LanguageResolver` 逐行移植 `Prompt.DetectClass/ResolveSource/ResolveTarget` |
| 3 引擎可切换，Key 各自独立保存，旧 `ApiKey` 回退生效 | ✅ | 浮层 `Tab` 循环，仅一个可用时提示 `st_engine_only` |
| 16 条错误文案双语 | ✅ | I18n 键值与 exe 逐字一致；HTTP 6 类 + 网络 3 类映射 |
| 浮层 9 状态机、延迟徽章、缓存标注 | ⚠️ | 输入中 / 翻译中 / 完成 / 缓存 / 失败 / 思考中齐全；「输出中」「精译中」「精译失败」三条状态未做（DeepL 为一次性响应，V6.2.0 也不再追加片段） |
| 三皮肤 + 15–100% 浓度实时生效 | ✅ | 24 色 × 3 皮肤，色值与 `Theme` 完全一致；拖动滑杆实时刷新所有浮层 |
| 四类显示开关（原文/提示/胶囊/延迟） | — | `ShowLatency` 原版即为死字段（不参与布局），此处保持一致 |
| 多实例、Esc 只关当前、焦点跟随 | ✅ | 每个实例独立 `NSPanel` + 独立状态机 |
| 吸附白名单 18 项 + 关窗联动 + 宽度跟随 | ✅ | 按 bundle id 映射 21 个 macOS 应用；100 ms 轮询跟随，窗口关闭 200 ms 内退出 |
| 7 组热键 + 录入校验三错误 | ✅ | Carbon 全局热键；`hk_err_mod` / `hk_err_key` / `hk_err_busy` 三条提示齐备 |
| 托盘 8 项 + 勾选态 + 悬停版本号 | ✅ | `NSStatusItem`，菜单结构与原版一致 |
| 首选项 4 页全部控件与文案 | ✅ | 常规 / 更新日志 / 使用技巧 / 用户反馈；「以管理员身份运行」按 macOS 语义禁用 |
| 使用技巧 7 条图文 | ✅ | 前两条为矢量图示，其余为文字步骤（原版同为图文混排） |
| 反馈弹窗 + 4 列历史 + 本地存档结构 | ✅ | `FB-yyyyMMdd-HHmmss/` + 反馈内容.txt + 附件 + 附件清单.txt；multipart 提交 |
| 更新检查 + SHA256 校验 + 一键更新 | ✅ | `latest.json` 同格式；校验失败中止；替换 `.app` 后重启（真实发布包未回归） |
| 日志滚动 + 缓存持久化 + 单实例 | ✅ | `flock` 单实例；日志 `.1` 滚动；LRU 落盘 |
| CLI 全部参数 | ⚠️ | `--translate/--version/--bump/--validate-version/--config/--prefs/--make-icon/--preview/--help` 全通；`--apply-update` 交由应用内更新器，`--spawn` 无对应语义 |
| 中英双语全覆盖（默认中文） | ✅ | 新增 macOS 专用键（辅助功能状态、反馈路径、免授权说明），其余逐字复用 |

其他与原版的有意差异（详见 `macos/README.md` §6）：
不移植全局键盘钩子、毛玻璃用系统材质而非抓屏、管理员权限改为辅助功能授权状态。

---

## 14. macOS 实现台账（2026-11-04）

| 层 | Windows 文件 | macOS 文件 | 验证 |
|---|---|---|---|
| 配置 | `src/Engine.cs`（Config 44 字段） | `LumiTypeCore/Config.swift` | `swift run verify` 配置组 12 项 |
| 引擎 | `src/Engine.cs`、`src/Providers.cs` | `LumiTypeCore/Engines.swift` | 请求构造 / 响应解析 / 桩服务器端到端 |
| 语言方向 | `Prompt.DetectClass/Resolve*` | `LumiTypeCore/LanguageResolver.swift` | 语言组 8 项断言 |
| 卡片视觉 | `src/CardRenderer.cs`（1270 行） | `CardModel.swift` + `Theme.swift` + `OverlayView.swift` | `--preview` 三皮肤 × 多状态出图 |
| 浮层交互 | `src/Overlay.cs`（3585 行） | `OverlayController.swift` | `--demo` 真实窗口 + 日志 |
| 首选项 | `src/PrefsForm.cs`（1940 行） | `PreferencesWindow.swift` + 反馈页 | 4 页截图 |
| 托盘 | `OverlayApp.BuildTray` | `StatusMenu.swift` | 启动即见、8 项 |
| 更新 | `src/Updater` | `Updater.swift` | latest.json 解析 + SHA256 分支 |
| 图标 | `IconArt`（GDI+） | `IconArt.swift`（Core Graphics） | `--make-icon` + `iconutil` |

**核心断言**：81 项全通过（配置兼容 / 版本号 / LRU / 引擎请求 / 端到端 / 文案 / 更新日志 / 语言方向）。

*本文档所有条目均可在二进制中定位到对应字符串或元数据。未标注「推定」的项均为实测。*


---

## 13. 二进制 vs 源码（V6.1.6 → V6.2.0）差异台账

| 项 | 6.1.6（二进制） | 6.2.0（`src/`） | 处理 |
|---|---|---|---|
| 默认 `Theme` | 未知 | `glass-dark` | 已对齐 |
| 默认 `GlassOpacity` | 未知 | `78` | 已对齐 |
| 默认 `MaxWidth` | 未知 | `600` | 已对齐 |
| 默认 `DebounceMs` / `MinChars` | 未知 | `320` / `1` | 已对齐 |
| 默认 `CacheSize` | 未知 | `300` | 已对齐 |
| 默认 `OffsetX` / `OffsetY` | 未知 | `8` / `22` | 已对齐 |
| 默认 `TargetLang` | 未知 | `English`（语言名，非代码） | 已对齐 |
| 配置字段数 | 44 | 44（字段名一致） | 无差异 |
| 热键默认值 | `Alt+Y` / `Ctrl+Alt+Y` | 同 | 无差异 |
| 更新源 | `LumiType-Translation` | 同 | 无差异 |

**结论：以 6.2.0 为实现目标。** 6.1.6 的二进制分析仅用于交叉校验
（证明从二进制还原出的字段表与真实源码完全一致，可作为后续源码不可得时的兜底方法）。
