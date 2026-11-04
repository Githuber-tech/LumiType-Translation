# LumiType 灵译 · macOS 迁移可行性评估

> 评估对象：`https://github.com/Githuber-tech/LumiType-Translation` v6.1.6
> 方法：静态解析 PE / .NET 元数据（未运行程序，macOS 侧即可完成）
> 结论先行：**可以拆解，可以重构为 macOS 原生可安装应用。** 但仓库里没有源码，需要先解决源码来源问题。

---

## 0. 一个必须先纠正的事实

你提到「代码全部托管至 GitHub」。实际检查结果是：**仓库里没有一行源码。**

```
git clone --depth 1 https://github.com/Githuber-tech/LumiType-Translation
```

克隆后全部内容，共 5 个文件、13 次提交、9 个 tag：

| 文件 | 大小 | 性质 |
|---|---|---|
| `LumiType.exe` | 1,228,192 B | 编译产物 |
| `README.md` | 3,545 B | 文档 |
| `favicon.ico` | 419,110 B | 资源 |
| `latest.json` | 1,035 B | 升级清单 |
| `preview.png` | 76,720 B | 截图 |

13 次提交的 message 全部形如 `publish v6.1.6`，即这是**发布流水线仓库**（存放产物 + 升级清单），不是源码仓库。

所以「源码是否还在你手上」这件事必须先确认。两种情形都不影响可行性，只影响起点：

- **源码还在**（本地/私有仓库）→ 直接进入阶段 1。
- **源码丢了** → 我先把 exe 反编译回 C# 工程。.NET 的 IL 保留了类型、方法、字符串、资源等全部结构信息，还原度足够重新编译，丢的一般是注释、部分局部变量名和编译器重排的写法。这个我可做，且已经验证过可解析（见下）。

完整性核对：本地 exe 的 SHA256 = `c494a8b604de28fe112904ce73201b54bc1300082529156623a42cf7f5faa841`，与 `latest.json` 中登记值一致，样本未被篡改。

---

## 1. 技术栈指纹（实测结果）

```
file LumiType.exe
→ PE32 executable (GUI) Intel 80386 Mono/.Net assembly, for MS Windows
```

| 项目 | 实测值 |
|---|---|
| 运行时 | .NET Framework 4.x（`v4.0.30319`，`mscorlib 4.0.0.0`） |
| 图形栈 | System.Windows.Forms（79 处类型引用）+ System.Drawing / GDI+（39 处） |
| 程序集引用 | only 6 个：mscorlib、System.Windows.Forms、System.Drawing、System.Web.Extensions、System、System.Net.Http |
| 第三方依赖 | **零**。无 Newtonsoft、无 DevExpress、无任何商业控件 |
| 类型数 | 62 |
| 方法数 | 531 |
| P/Invoke | **53 个**（user32 46、gdi32 4、dwmapi 1、kernel32 1、shell32 1） |
| 位宽 | x86（PE32），SysWOW64 运行 |
| 分发形态 | 单文件绿色版，无安装器 |

这是个非常好的起点：**纯自研、零第三方库、无 COM 依赖、无加密狗**。前面担心的最难缠的三类耦合全部不存在。

---

## 2. 架构还原

从 TypeDef / MethodDef 可以完整重建模块划分：

```
LumiType
├── 程序入口与外壳
│   ├── Entry / Program          主入口、单实例、应用内重启
│   ├── Cli                      命令行模式（--api-key / --version / --help）
│   ├── Config                   配置读写、版本迁移（MigrateApi/MigrateLangs）
│   └── Log                      分级日志
├── UI 层（WinForms + GDI+ 全自绘）
│   ├── OverlayForm             浮层主窗体（OnPaint 手绘全部像素）
│   ├── InputForm               输入态
│   ├── HotkeyForm              快捷键录入
│   ├── PrefsForm               首选项（General/Glass/Log/Tips 四个分页）
│   ├── FeedbackDialog          意见反馈
│   ├── GlassSlider             透明度滑杆（自绘控件）
│   ├── CardRenderer/CardLayout/CardModel/Theme  卡片渲染引擎 + 主题系统
│   ├── IconArt / TipDiagram    图标与示意图绘制
│   └── I18n                    中/英双语
├── 平台交互层（全部依赖 Win32）
│   ├── Native                  53 个 DllImport 的封装
│   ├── OverlayInstance         多浮层实例管理
│   ├── HotkeyForm/RegisterHotkeys
│   └── SetWinEventHook / SetWindowsHookEx / UpdateLayeredWindow
├── 业务核心
│   ├── DeepLClient / TranslationClient / TranslateGoogle / TranslateLlm
│   ├── Prompt                  提示词构造
│   └── LruCache                译文缓存
└── 分发
    ├── Updater / UpdateInfo / LumiVersion   latest.json + SHA256 校验 + 自替换
    └── ChangelogAuto
```

关键判断：**这个程序是「自绘 UI」而非「控件堆叠」**。`OnPaint` + `GraphicsPath` + `LinearGradientBrush` + `UpdateLayeredWindow` 意味着视觉层是纯像素绘制，业务逻辑与 WinForms 控件树的耦合度反而比典型 WinForms 应用低。对迁移是利好——UI 层可以整体替换而不牵动业务。

---

## 3. 平台耦合清单与 macOS 映射

53 个 Win32 调用按功能归类，逐条对应 macOS 原生方案：

| # | Windows 能力 | 用途 | macOS 对应方案 | 难度 |
|---|---|---|---|---|
| 1 | `RegisterHotKey` / `UnregisterHotKey` | 全局热键 Alt+Y | Carbon `RegisterEventHotKey`（仍可用且稳定）或 `CGEventTap` | 低 |
| 2 | `SetWindowsHookExW` + `CallNextHookEx` | 低级键鼠钩子、滚轮穿透 | `CGEventTap`（需辅助功能授权） | 中 |
| 3 | `SetWinEventHook` / `UnhookWinEvent` | 前台窗口切换跟随 | `NSWorkspace.didActivateApplicationNotification` | 低 |
| 4 | `GetGUIThreadInfo` + `GUITHREADINFO` | **取目标程序的光标插入点坐标** | `AXUIElement` + `kAXSelectedTextRangeAttribute` + `AXBoundsForRange` | **高** |
| 5 | `UpdateLayeredWindow` + `BLENDFUNCTION` | 逐像素 Alpha 的悬浮窗 | `NSWindow`（borderless, `.nonactivatingPanel`）+ `CALayer` 合成 | 中 |
| 6 | `SetWindowLongPtr(GWL_EXSTYLE, WS_EX_NOACTIVATE)` | 浮层不抢焦点 | `NSPanel` 的 `styleMask = [.nonactivatingPanel, .borderless]` | 低 |
| 7 | `GetForegroundWindow` / `SetForegroundWindow` / `AttachThreadInput` | 焦点接管与归还 | `NSRunningApplication.activate(options:)` | 中 |
| 8 | `keybd_event` / `QueueCtrlV` | 模拟 Ctrl+V 把译文粘回去 | `NSPasteboard` 写入 + `CGEvent` 合成 ⌘V | 中 |
| 9 | `PrintWindow` / `GrabScreenBackdrop` / `TryPrintBackdrop` | 抓目标窗口做毛玻璃底图 | `ScreenCaptureKit` / `CGWindowListCreateImage`（需屏幕录制授权） | 中 |
| 10 | `DwmGetColorizationColor` | 取系统强调色 | `NSColor.controlAccentColor` | 低 |
| 11 | `EnumWindows` / `FindWindow` / `GetClassName` / `WindowFromPoint` | 吸附目标枚举 | `CGWindowListCopyWindowInfo` + `NSWorkspace.runningApplications` | 中 |
| 12 | 注册表 `Run` 键 | 开机自启 | `SMAppService.mainApp.register()`（macOS 13+） | 低 |
| 13 | `Shell_NotifyIcon` | 托盘常驻 | `NSStatusItem` + `NSMenu` | 低 |
| 14 | `SetProcessDPIAware` | DPI 适配 | 无对应，Retina 由 `NSScreen.backingScaleFactor` 自动处理 | 低 |
| 15 | `SetCurrentProcessExplicitAppUserModelID` | 任务栏图标身份 | 无对应，`CFBundleIdentifier` 取代 | 低 |
| 16 | GDI+ 全部（`GraphicsPath` / `LinearGradientBrush` / `ColorMatrix` …） | 全自绘 UI | SwiftUI `Canvas` 或 Core Graphics `CGContext` | 中 |
| 17 | `Microsoft.Win32.Registry` | 配置持久化 | `UserDefaults` / `~/Library/Application Support/LumiType/settings.json` | 低 |

**唯一致命的一项是 #4**。Windows 的 `GetGUIThreadInfo` 可以直接拿到任意前台窗口的文本插入符矩形，这是 LumiType「浮层贴在光标旁」体验的技术基础。macOS 的 AX API 能做到，但**不同 App 的实现质量差异极大**：原生 Cocoa 应用（Safari、Notes、Xcode）稳定；Electron 系（VS Code、Slack）、部分 IM（微信、钉钉）经常返回空值或错误矩形。必须有降级链：`AX caret → 鼠标位置 → 屏幕固定锚点`。

---

## 4. 三条路线

| | A. 兼容层 | B. Avalonia 跨平台 | C. Swift 原生重写 ★推荐 |
|---|---|---|---|
| 做法 | CrossOver / Whisky / 虚拟机跑原 exe | .NET 8 + Avalonia 重写 UI，复用 C# 业务逻辑 | Swift + SwiftUI/AppKit 全重写 |
| 是否 Mac 原生 | 否 | 否（像 Mac 的跨平台壳） | 是 |
| 业务逻辑 | 0 改动 | 大部分可直接搬 | 需翻译为 Swift |
| 工期估算 | 0.5 天 | 1.5～2.5 周 | 3～5 周 |
| 长期可维护 | 差（升级即失效） | 中 | 好 |
| 交付门槛 | 用户需装 CrossOver（付费） | 无 | 无 |

**推荐 C**，理由：
1. 你明确要的是「Mac 原生」。B 路线交付的东西在 Dock 图标、菜单栏、字体渲染、动画曲线上仍会露出 Windows 味，且 Avalonia 在 macOS 上做无边框非激活面板 + 逐像素透明，仍要写一堆 ObjC 互操作，等于绕一圈回到 C。
2. 业务逻辑体量小得可控。去掉 UI 与平台层，真正的业务代码是：DeepL/Google/LLM 三个 HTTP 客户端、JSON 解析、LRU 缓存、提示词拼接、i18n 词表、版本比较。这些用 Swift 重写大约 1500～2000 行，是 1～2 天的事。
3. 零第三方依赖，不存在「某个库在 Darwin 上没有构建」的死结。

**如果工期是第一约束**：先出 B 路线可用版本，再逐步迁 C。但不要把 B 当终点。

---

## 5. 硬约束与风险（必须提前知道）

| 风险 | 影响 | 处置 |
|---|---|---|
| **辅助功能授权** | 全局热键、CGEventTap、模拟 ⌘V、AX 取光标，全部依赖用户在「系统设置 → 隐私与安全性 → 辅助功能」手动勾选。Windows 上开箱即用，macOS 上必须做首次引导 | 首启弹引导页 + `AXIsProcessTrustedWithOptions` 检测 + 未授权时降级为「仅手动触发」 |
| **屏幕录制授权** | 毛玻璃底图（抓目标窗口）需要「屏幕录制」权限 | 未授权时退化为纯色/半透明背景，不阻塞主流程 |
| **App Store 上架不可行** | 全局键鼠监听 + 跨应用抓屏 + AX 操控，三项都踩 App Store 审核红线 | 只能走**直接分发**：Developer ID 签名 + 公证（notarization）+ DMG。这条路完全合法，只是没有商店流量 |
| **AX 兼容性参差** | 微信/钉钉/Electron 类应用可能取不到光标矩形 | 三级降级链 + 每应用记忆上次可用策略 |
| **.NET Framework 无法跨平台** | 4.x 没有 macOS 运行时，不存在「直接编译到 Mac」的捷径 | 必须迁 .NET 8 或重写，这正是本评估的前提 |
| **自动更新机制重写** | 现有 `Updater` 是 exe 自替换逻辑 | macOS 侧改为 Sparkle 2（业界标准）或自研 DMG 替换 + 签名校验 |

自动更新有个额外好处：`latest.json` + SHA256 的清单格式可以原样保留，只需把更新动作从「替换 exe」换成「替换 .app 并重启」。

---

## 6. 工作量估算

以 v6.1.6 的 531 方法为基线，C 路线：

| 阶段 | 内容 | 估算 | 置信度 |
|---|---|---|---|
| 0 | 源码获取或反编译重建 + 模块盘点 | 1～2 天 | 高 |
| 1 | 业务核心移植（3 个翻译客户端、缓存、i18n、配置、版本） | 3～4 天 | 高 |
| 2 | 平台层（热键、AX 取光标、浮层窗口、模拟粘贴、托盘、自启） | 8～12 天 | 中 |
| 3 | UI 重建（浮层自绘、卡片渲染、主题/皮肤、首选项、反馈） | 6～9 天 | 中 |
| 4 | 权限引导、签名、公证、DMG、Sparkle 更新 | 2～3 天 | 高 |
| | **合计** | **约 20～30 人日** | |

阶段 2 的不确定性最大，取决于 AX 降级策略要打磨到多细。

---

## 7. 下一步

需要你确认或提供：

1. **源码在哪** —— 本地源码工程，还是需要我从 exe 反编译重建？（后者我今天就能出一份可编译的 C# 工程）
2. **最低支持系统** —— 建议 macOS 13 Ventura 起（`SMAppService` 需要 13+），覆盖 2022 年后的机器。
3. **分发方式** —— 是否接受「不上市、DMG + 公证直接分发」。若坚持上架 App Store，功能需大幅裁剪（去掉跨应用抓屏与全局键盘监听），产品价值会损失一半。
4. **是否需要保留 CLI 模式** —— 现有 `LumiType.Cli` 有 `--api-key / --version` 等子命令，macOS 侧可保留为 `.app/Contents/MacOS/LumiType --cli`。

### 验收基线怎么定

Windows 版现有行为就是规格书。迁移期我会用你在 Windows 上跑的 20 条真实用例（每条的原文、目标应用、期望译文位置）做回归对照，逐条打勾。这比读代码更能保证「重构后是同一个产品」。

---

*本报告全部结论来自对 exe 的静态解析，未运行程序。标注「估算」的工期为区间估计，非承诺。*

---

## 8. 决策记录（2026-11-04 确认）

| 事项 | 结论 |
|---|---|
| 源码 | 已丢失，仅有 exe。走反编译重建 + 原生重写路线 |
| 还原度要求 | **1:1**，所有功能、设置、说明不得缺失 |
| 最低系统 | macOS 13 Ventura |
| 分发方式 | 不上架 App Store，Developer ID 签名 + 公证 + DMG |
| 修复方式 | 后续遇到问题逐项具体修复 |

功能基线已固化为 [`feature-inventory.md`](feature-inventory.md)，共 12 节、
含 44 个配置字段、16 条错误码、10 种语言、8 项托盘菜单、4 个首选项分页、
7 条使用技巧、8 组热键、18 项吸附白名单。macOS 侧验收以该文档逐项打勾为准。

阶段 1（业务核心）代码已落地于 [`../macos`](../macos)，81 项断言全部通过。
