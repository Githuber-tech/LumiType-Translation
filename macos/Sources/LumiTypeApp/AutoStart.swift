import AppKit
import LumiTypeCore
import ServiceManagement

/// 开机启动。
///
/// Windows 版写注册表 `HKCU\...\Run`；macOS 的官方对应物是
/// `SMAppService.mainApp`（macOS 13+，需要 .app 形态）。
/// 从源码直接跑（非 bundle）时退化为 LaunchAgent plist，保证开发期也能验证。
enum AutoStart {

    static var isEnabled: Bool {
        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier != nil {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: agentPlist.path)
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier != nil {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                Log.shared.info("SMAppService \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
                // 继续走 LaunchAgent 兜底
            }
        }
        return setAgent(enabled)
    }

    // MARK: - LaunchAgent 兜底

    private static var agentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.lumitype.mac.plist")
    }

    private static var launchTarget: String {
        // 在 .app 里时指向 bundle，否则指向可执行文件
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" { return bundle.path }
        return CommandLine.arguments.first ?? bundle.path
    }

    private static func setAgent(_ enabled: Bool) -> Bool {
        let fm = FileManager.default
        if !enabled {
            try? fm.removeItem(at: agentPlist)
            shell("/bin/launchctl", ["bootout", "gui/\(getuid())/com.lumitype.mac"])
            return true
        }
        let plist: [String: Any] = [
            "Label": "com.lumitype.mac",
            "ProgramArguments": [launchTarget],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
        do {
            try fm.createDirectory(at: agentPlist.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentPlist)
            shell("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentPlist.path])
            return true
        } catch {
            Log.shared.info("LaunchAgent write failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func shell(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
    }
}
