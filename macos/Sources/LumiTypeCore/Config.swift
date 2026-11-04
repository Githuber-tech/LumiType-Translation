import Foundation

/// 与原版 `LumiType.Config` 完全对齐的 44 个字段。
///
/// 设计要点（复刻原版行为）：
/// 1. 缺失字段用默认值补齐，不因新增/删除字段而报错；
/// 2. 类型不符（数字写成字符串等）时回退默认值，不抛异常；
/// 3. 文件损坏时改名为 `settings.json.corrupt-<时间戳>` 隔离后重建；
/// 4. DeepL 的 Key 优先取 `DeeplKey`，为空时回退旧字段 `ApiKey`
///    —— 这是 v6.1.6 修的 403 事故，必须在 Mac 版保留。
public struct Config: Sendable {

    // 网络与端点
    public var baseUrl: String
    public var apiKey: String
    public var provider: String
    public var deeplKey: String
    public var googleKey: String
    public var llmKey: String
    public var llmEndpoint: String
    public var llmModel: String
    public var timeoutMs: Int
    public var updateUrl: String
    public var uiLang: String
    public var feedbackEndpoint: String

    // 语言
    public var sourceLang: String
    public var targetLang: String
    public var pinSource: Bool
    public var pinTarget: Bool
    public var pairLang: String
    public var autoDirection: Bool

    // 翻译行为
    public var realtime: Bool
    public var qualityModel: Bool
    public var debounceMs: Int
    public var minChars: Int
    public var cacheSize: Int

    // 外观
    public var theme: String
    public var fontScale: Double
    public var maxWidth: Int
    public var glassOpacity: Int
    public var offsetX: Int
    public var offsetY: Int
    public var showSource: Bool
    public var showHints: Bool
    public var showPills: Bool
    public var showLatency: Bool

    // 交互
    public var hotkeyToggle: String
    public var hotkeyClipboard: String
    public var proxyMode: String
    public var proxyServer: String
    public var debugLog: Bool
    public var pinned: Bool
    public var autoStart: Bool
    public var runAsAdmin: Bool
    public var pinnedX: Int
    public var pinnedY: Int

    // 元信息（不写入文件）
    public var filePath: String

    // MARK: - 默认值
    //
    // 标注 [推定] 的项无法从二进制直接读出，需在 Windows 首次运行时导出 settings.json 核对。

    public static func defaults(filePath: String) -> Config {
        Config(
            baseUrl: "",
            apiKey: "",
            provider: Provider.deepl.rawValue,
            deeplKey: "",
            googleKey: "",
            llmKey: "",
            llmEndpoint: "https://api.deepseek.com/v1/chat/completions",
            llmModel: "deepseek-chat",
            timeoutMs: 20_000,                 // src/Engine.cs 实测
            updateUrl: "https://raw.githubusercontent.com/Githuber-tech/LumiType-Translation/main/latest.json",
            uiLang: Config.systemUiLang(),
            feedbackEndpoint: "https://formsubmit.co/ajax/alydomn@foxmail.com",
            sourceLang: "",                    // src/Engine.cs 实测：空串 = 自动识别
            targetLang: "English",             // src/Engine.cs 实测：存的是语言名，不是代码
            pinSource: false,
            pinTarget: false,
            pairLang: "",
            autoDirection: true,
            realtime: true,
            qualityModel: true,
            debounceMs: 320,                   // src/Engine.cs 实测
            minChars: 1,                       // src/Engine.cs 实测
            cacheSize: 300,                    // src/Engine.cs 实测
            theme: "glass-dark",               // src/Engine.cs 实测
            fontScale: 1.0,
            maxWidth: 600,                     // src/Engine.cs 实测
            glassOpacity: 78,                  // src/Engine.cs 实测
            offsetX: 8,                        // src/Engine.cs 实测
            offsetY: 22,                       // src/Engine.cs 实测
            showSource: true,
            showHints: true,
            showPills: true,
            showLatency: true,
            hotkeyToggle: "Alt+Y",
            hotkeyClipboard: "Ctrl+Alt+Y",
            proxyMode: "system",
            proxyServer: "",
            debugLog: false,
            pinned: false,
            autoStart: false,
            runAsAdmin: false,
            pinnedX: 0,
            pinnedY: 0,
            filePath: filePath
        )
    }

    /// 首次运行按系统语言决定界面语言（原版是中文优先）
    public static func systemUiLang() -> String {
        let preferred = Locale.preferredLanguages.first ?? "zh"
        return preferred.lowercased().hasPrefix("zh") ? "zh" : "en"
    }
}

// MARK: - 读写

extension Config {

    /// 配置目录：`~/Library/Application Support/LumiType/`
    /// 对应原版的「exe 旁的 config\\ 目录」
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("LumiType", isDirectory: true)
    }

    public static func defaultFile() -> URL {
        defaultDirectory().appendingPathComponent("settings.json")
    }

    /// 从磁盘加载。文件不存在 → 全默认；解析失败 → 隔离后返回默认。
    public static func load(from url: URL = Config.defaultFile()) -> Config {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return defaults(filePath: path)
        }
        do {
            let data = try Data(contentsOf: url)
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let dict = obj as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            return Config(dictionary: dict, filePath: path)
        } catch {
            quarantine(url: url)
            return defaults(filePath: path)
        }
    }

    /// 损坏文件隔离，保留现场供排查（原版：`config corrupt, quarantined to …`）
    @discardableResult
    public static func quarantine(url: URL) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let target = url.appendingPathExtension("corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    /// 写入磁盘。目录不存在时自动创建；原子写入避免半截文件。
    public func save(to url: URL? = nil) throws {
        let target = url ?? URL(fileURLWithPath: filePath.isEmpty ? Config.defaultFile().path : filePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: dictionary(),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: target, options: .atomic)
    }

    /// 导出为字典，键名与原版 settings.json 完全一致
    public func dictionary() -> [String: Any] {
        [
            "BaseUrl": baseUrl,
            "ApiKey": apiKey,
            "Provider": provider,
            "DeeplKey": deeplKey,
            "GoogleKey": googleKey,
            "LlmKey": llmKey,
            "LlmEndpoint": llmEndpoint,
            "LlmModel": llmModel,
            "TimeoutMs": timeoutMs,
            "UpdateUrl": updateUrl,
            "UiLang": uiLang,
            "FeedbackEndpoint": feedbackEndpoint,
            "SourceLang": sourceLang,
            "TargetLang": targetLang,
            "PinSource": pinSource,
            "PinTarget": pinTarget,
            "PairLang": pairLang,
            "AutoDirection": autoDirection,
            "Realtime": realtime,
            "QualityModel": qualityModel,
            "DebounceMs": debounceMs,
            "MinChars": minChars,
            "CacheSize": cacheSize,
            "Theme": theme,
            "FontScale": fontScale,
            "MaxWidth": maxWidth,
            "GlassOpacity": glassOpacity,
            "OffsetX": offsetX,
            "OffsetY": offsetY,
            "ShowSource": showSource,
            "ShowHints": showHints,
            "ShowPills": showPills,
            "ShowLatency": showLatency,
            "HotkeyToggle": hotkeyToggle,
            "HotkeyClipboard": hotkeyClipboard,
            "ProxyMode": proxyMode,
            "ProxyServer": proxyServer,
            "DebugLog": debugLog,
            "Pinned": pinned,
            "AutoStart": autoStart,
            "RunAsAdmin": runAsAdmin,
            "PinnedX": pinnedX,
            "PinnedY": pinnedY
        ]
    }
}

// MARK: - 字典还原（宽容解析）

extension Config {

    public init(dictionary d: [String: Any], filePath: String) {
        let def = Config.defaults(filePath: filePath)
        func s(_ k: String, _ fallback: String) -> String {
            if let v = d[k] as? String { return v }
            if let v = d[k] as? NSNumber { return v.stringValue }
            return fallback
        }
        func i(_ k: String, _ fallback: Int) -> Int {
            if let v = d[k] as? Int { return v }
            if let v = d[k] as? NSNumber { return v.intValue }
            if let v = d[k] as? String, let n = Int(v.trimmingCharacters(in: .whitespaces)) { return n }
            return fallback
        }
        func b(_ k: String, _ fallback: Bool) -> Bool {
            if let v = d[k] as? Bool { return v }
            if let v = d[k] as? NSNumber { return v.boolValue }
            if let v = d[k] as? String {
                let t = v.lowercased().trimmingCharacters(in: .whitespaces)
                if ["true", "1", "yes", "on"].contains(t) { return true }
                if ["false", "0", "no", "off"].contains(t) { return false }
            }
            return fallback
        }
        func db(_ k: String, _ fallback: Double) -> Double {
            if let v = d[k] as? Double { return v }
            if let v = d[k] as? NSNumber { return v.doubleValue }
            if let v = d[k] as? String, let n = Double(v.trimmingCharacters(in: .whitespaces)) { return n }
            return fallback
        }

        self.init(
            baseUrl: s("BaseUrl", def.baseUrl),
            apiKey: s("ApiKey", def.apiKey),
            provider: s("Provider", def.provider),
            deeplKey: s("DeeplKey", def.deeplKey),
            googleKey: s("GoogleKey", def.googleKey),
            llmKey: s("LlmKey", def.llmKey),
            llmEndpoint: s("LlmEndpoint", def.llmEndpoint),
            llmModel: s("LlmModel", def.llmModel),
            timeoutMs: i("TimeoutMs", def.timeoutMs),
            updateUrl: s("UpdateUrl", def.updateUrl),
            uiLang: s("UiLang", def.uiLang),
            feedbackEndpoint: s("FeedbackEndpoint", def.feedbackEndpoint),
            sourceLang: s("SourceLang", def.sourceLang),
            targetLang: s("TargetLang", def.targetLang),
            pinSource: b("PinSource", def.pinSource),
            pinTarget: b("PinTarget", def.pinTarget),
            pairLang: s("PairLang", def.pairLang),
            autoDirection: b("AutoDirection", def.autoDirection),
            realtime: b("Realtime", def.realtime),
            qualityModel: b("QualityModel", def.qualityModel),
            debounceMs: i("DebounceMs", def.debounceMs),
            minChars: i("MinChars", def.minChars),
            cacheSize: i("CacheSize", def.cacheSize),
            theme: s("Theme", def.theme),
            fontScale: db("FontScale", def.fontScale),
            maxWidth: i("MaxWidth", def.maxWidth),
            glassOpacity: i("GlassOpacity", def.glassOpacity),
            offsetX: i("OffsetX", def.offsetX),
            offsetY: i("OffsetY", def.offsetY),
            showSource: b("ShowSource", def.showSource),
            showHints: b("ShowHints", def.showHints),
            showPills: b("ShowPills", def.showPills),
            showLatency: b("ShowLatency", def.showLatency),
            hotkeyToggle: s("HotkeyToggle", def.hotkeyToggle),
            hotkeyClipboard: s("HotkeyClipboard", def.hotkeyClipboard),
            proxyMode: s("ProxyMode", def.proxyMode),
            proxyServer: s("ProxyServer", def.proxyServer),
            debugLog: b("DebugLog", def.debugLog),
            pinned: b("Pinned", def.pinned),
            autoStart: b("AutoStart", def.autoStart),
            runAsAdmin: b("RunAsAdmin", def.runAsAdmin),
            pinnedX: i("PinnedX", def.pinnedX),
            pinnedY: i("PinnedY", def.pinnedY),
            filePath: filePath
        )
    }

    /// 数值越界与非法枚举就地纠正，保证下游逻辑不会拿到脏值
    public func normalized() -> Config {
        var c = self
        c.glassOpacity = min(100, max(15, c.glassOpacity))   // 原版下限 30→15（V5.3.0）
        c.timeoutMs = min(120_000, max(1_000, c.timeoutMs))
        c.debounceMs = min(5_000, max(0, c.debounceMs))
        c.minChars = min(200, max(1, c.minChars))
        c.cacheSize = min(20_000, max(0, c.cacheSize))
        c.maxWidth = min(4_000, max(200, c.maxWidth))
        c.fontScale = min(3.0, max(0.6, c.fontScale))
        // src/PrefsForm.cs:279 的三选；未知值回落到默认 skin
        if !["paper-light", "glass-dark", "accent-glass"].contains(c.theme) {
            c.theme = "glass-dark"
        }
        if Provider(rawValue: c.provider) == nil { c.provider = Provider.deepl.rawValue }
        if !["zh", "en"].contains(c.uiLang) { c.uiLang = Config.systemUiLang() }
        if !["system", "direct", "manual"].contains(c.proxyMode) { c.proxyMode = "system" }
        return c
    }

    // MARK: - Key 解析

    /// DeepL 实际使用的 Key。
    /// v6.1.6 的修复点：先读 `DeeplKey`，为空才回退旧 `ApiKey`。
    public var effectiveDeepLKey: String {
        deeplKey.isEmpty ? apiKey : deeplKey
    }

    public var effectiveGoogleKey: String { googleKey }

    public var effectiveLlmKey: String { llmKey.isEmpty ? apiKey : llmKey }

    /// 当前选中引擎是否已配置 Key
    public func isConfigured(_ p: Provider) -> Bool {
        switch p {
        case .deepl: return !effectiveDeepLKey.isEmpty
        case .google: return !effectiveGoogleKey.isEmpty
        case .llm: return !effectiveLlmKey.isEmpty
        }
    }

    /// 已配置 Key 的引擎列表，供 Tab 键在引擎间循环
    public var configuredProviders: [Provider] {
        Provider.allCases.filter { isConfigured($0) }
    }
}
