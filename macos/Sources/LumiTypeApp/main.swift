import AppKit
import LumiTypeCore

// 先处理命令行：有参数就按 CLI 跑完退出，不创建 NSApplication，
// 这样 `LumiType --translate ...` 在脚本里不会卡在事件循环上。
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let code = AppCLI.runIfNeeded(cliArgs) {
    exit(code)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)     // 菜单栏常驻，不占 Dock（等价 LSUIElement）
app.run()
