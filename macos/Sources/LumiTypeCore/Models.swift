import Foundation

// MARK: - 引擎

/// 与原版 `Config.Provider` 取值完全一致：deepl / google / llm
public enum Provider: String, CaseIterable, Sendable {
    case deepl
    case google
    case llm

    /// 托盘/首选项中显示的引擎名（与原版 I18n 键 eng_* 对应）
    public func displayName(_ uiLang: String) -> String {
        switch (self, uiLang) {
        case (.deepl, _): return "DeepL"
        case (.google, "zh"): return "Google 翻译"
        case (.google, _): return "Google Translate"
        case (.llm, "zh"): return "LLM（DeepSeek 等）"
        case (.llm, _): return "LLM (DeepSeek etc.)"
        }
    }

    /// 卡片头部简写，对应原版 `EngineLabel`
    public var shortLabel: String {
        switch self {
        case .deepl: return "DeepL"
        case .google: return "Google"
        case .llm: return "LLM"
        }
    }
}

// MARK: - 语言

/// 原版 `Prompt.BuiltInTargets` 的 10 种语言，顺序与二进制中的字符串顺序一致。
public struct Language: Hashable, Sendable {
    /// 应用内部代码，写进 settings.json 的 SourceLang / TargetLang
    public let code: String
    /// 中文显示名
    public let nameZh: String
    /// 英文显示名（同时也是 DeepL 的语言名）
    public let nameEn: String
    /// DeepL API 使用的 target_lang 代码
    public let deepL: String

    public func displayName(_ uiLang: String) -> String {
        uiLang == "en" ? nameEn : nameZh
    }
}

public enum Languages {
    public static let all: [Language] = [
        Language(code: "zh-CN", nameZh: "简体中文", nameEn: "Simplified Chinese", deepL: "ZH"),
        Language(code: "zh-TW", nameZh: "繁體中文", nameEn: "Traditional Chinese", deepL: "ZH-HANT"),
        Language(code: "en", nameZh: "English", nameEn: "English", deepL: "EN"),
        Language(code: "ja", nameZh: "日本語", nameEn: "Japanese", deepL: "JA"),
        Language(code: "ko", nameZh: "한국어", nameEn: "Korean", deepL: "KO"),
        Language(code: "fr", nameZh: "Français", nameEn: "French", deepL: "FR"),
        Language(code: "de", nameZh: "Deutsch", nameEn: "German", deepL: "DE"),
        Language(code: "es", nameZh: "Español", nameEn: "Spanish", deepL: "ES"),
        Language(code: "pt", nameZh: "Português", nameEn: "Portuguese", deepL: "PT"),
        Language(code: "ru", nameZh: "Русский", nameEn: "Russian", deepL: "RU")
    ]

    /// 大小写不敏感查找，兼容 "zh" / "zh-cn" / "ZH" 等写法
    public static func find(_ code: String) -> Language? {
        guard !code.isEmpty else { return nil }
        let needle = code.lowercased()
        return all.first { $0.code.lowercased() == needle }
            ?? all.first { $0.nameEn.lowercased() == needle }
            ?? all.first { $0.nameZh == code }
    }

    /// 转成 DeepL 的 target_lang；未知代码原样大写透传
    public static func deepLCode(_ code: String) -> String {
        find(code)?.deepL ?? code.uppercased()
    }
}

// MARK: - 翻译结果

public struct TranslationOutcome: Sendable, Equatable {
    public var text: String
    public var provider: Provider
    public var latencyMs: Int
    /// 原文字数（原版状态行 `{0}ms · {1} 字`）
    public var charCount: Int
    /// 命中 LRU 缓存时为 true，状态行显示 `缓存 · {0} 字`
    public var cached: Bool
    /// DeepL 返回的 detected_source_language（用于自动识别）
    public var detectedSource: String?

    public init(
        text: String,
        provider: Provider,
        latencyMs: Int,
        charCount: Int,
        cached: Bool = false,
        detectedSource: String? = nil
    ) {
        self.text = text
        self.provider = provider
        self.latencyMs = latencyMs
        self.charCount = charCount
        self.cached = cached
        self.detectedSource = detectedSource
    }
}

// MARK: - 错误

/// 16 条错误码与原版一一对应（见 I18n 表的 e_* / err_empty* 键）。
public struct EngineError: Error, Equatable, Sendable {
    public let code: String
    /// 可选的原始细节，仅写日志，不显示给用户
    public let detail: String?

    public init(_ code: String, detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    public func message(_ uiLang: String) -> String {
        I18n.shared.t(code, uiLang)
    }

    /// HTTP 状态码 → 错误码。原版只对这 6 个状态码做专门映射。
    public static func from(status: Int, body: String?) -> EngineError {
        switch status {
        case 400: return EngineError("e_400", detail: body)
        case 401: return EngineError("e_401", detail: body)
        case 402: return EngineError("e_402", detail: body)
        case 403: return EngineError("e_403", detail: body)
        case 429: return EngineError("e_429", detail: body)
        case 456: return EngineError("e_456", detail: body)
        default: return EngineError("e_conn", detail: "HTTP \(status)")
        }
    }

    /// URLError → 错误码：DNS 与连接失败分开，其余归为超时/连接
    public static func from(urlError: URLError) -> EngineError {
        switch urlError.code {
        case .timedOut: return EngineError("e_timeout", detail: urlError.localizedDescription)
        case .cannotFindHost, .dnsLookupFailed:
            return EngineError("e_dns", detail: urlError.localizedDescription)
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotConnectToHost, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return EngineError("e_conn", detail: urlError.localizedDescription)
        default: return EngineError("e_conn", detail: urlError.localizedDescription)
        }
    }
}
