import AppKit
import LumiTypeCore

/// 运行期路径。对应原版「exe 旁边」的三个目录：
/// `config\` → `~/Library/Application Support/LumiType/`
/// `logs\`   → `.../logs/`
/// `feedback\` → `.../feedback/`
enum AppPaths {
    static var support: URL { Config.defaultDirectory() }
    static var configFile: URL { Config.defaultFile() }
    static var logs: URL { support.appendingPathComponent("logs", isDirectory: true) }
    static var feedback: URL { support.appendingPathComponent("feedback", isDirectory: true) }
    static var cache: URL { support.appendingPathComponent("transcache.json") }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// 分级日志：`logs/lumitype-yyyyMMdd.log`，单文件滚动 `.1`。
/// 行首时间戳格式与原版一致（`HH:mm:ss.fff`）。
final class Log {
    static let shared = Log()

    private let queue = DispatchQueue(label: "com.lumitype.log")
    private let stamp: DateFormatter
    private let timeOnly: DateFormatter
    private var handle: FileHandle?
    private var currentDay = ""
    private let maxBytes = 2 * 1024 * 1024

    private init() {
        stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd"
        timeOnly = DateFormatter()
        timeOnly.dateFormat = "HH:mm:ss.SSS"
    }

    var debugEnabled: Bool = false

    /// 调试级别：仅在 `DebugLog = true` 时落盘
    func debug(_ message: String) {
        guard debugEnabled else { return }
        write(message)
    }

    /// 常规级别：始终落盘（错误与关键动作）
    func info(_ message: String) {
        write(message)
    }

    private func write(_ message: String) {
        let now = Date()
        let day = stamp.string(from: now)
        let line = timeOnly.string(from: now) + "  " + message + "\n"
        queue.async { [weak self] in
            guard let self else { return }
            AppPaths.ensure(AppPaths.logs)
            if self.handle == nil || self.currentDay != day {
                self.openFile(day: day)
            }
            if let data = line.data(using: .utf8) {
                try? self.handle?.write(contentsOf: data)
            }
        }
    }

    private func openFile(day: String) {
        try? handle?.close()
        handle = nil
        let url = AppPaths.logs.appendingPathComponent("lumitype-\(day).log")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        // 单文件滚动：超过 2MB 就把当前文件挪成 .1（覆盖旧 .1）
        if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxBytes {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        currentDay = day
    }
}

/// 配置的唯一持有者。
/// 浮层、托盘、首选项都从这里取当前配置，改完统一 `save()+broadcast`。
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config: Config
    private var observers: [UUID: (Config) -> Void] = [:]

    private init() {
        config = Config.load().normalized()
        Log.shared.debugEnabled = config.debugLog
    }

    func reload() {
        config = Config.load().normalized()
        Log.shared.debugEnabled = config.debugLog
        notify()
    }

    func update(_ mutate: (inout Config) -> Void) {
        var c = config
        mutate(&c)
        config = c.normalized()
        try? config.save()
        Log.shared.debugEnabled = config.debugLog
        notify()
    }

    func save() {
        try? config.save()
    }

    @discardableResult
    func observe(_ block: @escaping (Config) -> Void) -> UUID {
        let token = UUID()
        observers[token] = block
        return token
    }

    func remove(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    private func notify() {
        let snapshot = config
        for block in observers.values { block(snapshot) }
    }

    var uiLang: String { config.uiLang }

    func t(_ key: String) -> String { I18n.shared.t(key, uiLang) }

    func t(_ key: String, _ args: [String]) -> String { I18n.shared.t(key, uiLang, args) }
}
