import Foundation

// MARK: - 协议

/// 三个引擎的共同契约。请求构造与响应解析分离，保证可以离线做单元测试。
public protocol TranslationEngine: Sendable {
    var provider: Provider { get }
    func makeRequest(text: String, source: String, target: String) throws -> URLRequest
    func parse(_ data: Data) throws -> (text: String, detected: String?)
}

// MARK: - DeepL

public struct DeepLClient: TranslationEngine {

    public static let defaultBase = "https://api-free.deepl.com/v2/"
    public static let userAgent = "LumiType/5.0"

    let key: String
    let baseUrl: String
    let quality: Bool
    /// DeepL 的 `context` 字段：原版用来稳定商务口吻，不计费
    let context: String

    public init(key: String, baseUrl: String = "", quality: Bool = true, context: String = "") {
        self.key = key
        self.baseUrl = baseUrl
        self.quality = quality
        self.context = context
    }

    public var provider: Provider { .deepl }

    private var endpoint: URL? {
        let base = baseUrl.isEmpty ? DeepLClient.defaultBase : baseUrl
        if base.hasSuffix("translate") { return URL(string: base) }
        let trimmed = base.hasSuffix("/") ? base : base + "/"
        return URL(string: trimmed + "translate")
    }

    public func makeRequest(text: String, source: String, target: String) throws -> URLRequest {
        guard !key.isEmpty else { throw EngineError("e_nokey_d") }
        guard let url = endpoint else { throw EngineError("e_conn", detail: "bad base url: \(baseUrl)") }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(DeepLClient.userAgent, forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = [
            "text": [text],
            "target_lang": Languages.deepLCode(target),
            "split_sentences": "nonewlines",
            "preserve_formatting": true
        ]
        if source != "auto", !source.isEmpty {
            body["source_lang"] = Languages.deepLCode(source)
        }
        if quality {
            body["model_type"] = "quality_optimized"
        }
        if !context.isEmpty {
            body["context"] = context
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }

    public func parse(_ data: Data) throws -> (text: String, detected: String?) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = obj["translations"] as? [[String: Any]],
            let first = list.first,
            let text = first["text"] as? String,
            !text.isEmpty
        else {
            throw EngineError("err_empty")
        }
        return (text, first["detected_source_language"] as? String)
    }
}

// MARK: - Google

public struct GoogleClient: TranslationEngine {

    public static let endpoint = "https://translation.googleapis.com/language/translate/v2"

    let key: String

    public init(key: String) {
        self.key = key
    }

    public var provider: Provider { .google }

    public func makeRequest(text: String, source: String, target: String) throws -> URLRequest {
        guard !key.isEmpty else { throw EngineError("e_nokey_g") }

        var comps = URLComponents(string: GoogleClient.endpoint)!
        var items = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "target", value: Languages.find(target)?.code.split(separator: "-").first.map(String.init) ?? target),
            URLQueryItem(name: "format", value: "text")
        ]
        if source != "auto", !source.isEmpty {
            items.append(URLQueryItem(name: "source",
                                      value: Languages.find(source)?.code.split(separator: "-").first.map(String.init) ?? source))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw EngineError("e_conn", detail: "bad google url") }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("LumiType/5.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    public func parse(_ data: Data) throws -> (text: String, detected: String?) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = obj["data"] as? [String: Any],
            let list = dataObj["translations"] as? [[String: Any]],
            let first = list.first,
            let raw = first["translatedText"] as? String,
            !raw.isEmpty
        else {
            throw EngineError("err_empty_g")
        }
        // Google 返回的是 HTML 转义文本
        return (Html.unescape(raw), first["detectedSourceLanguage"] as? String)
    }
}

// MARK: - LLM

public struct LlmClient: TranslationEngine {

    public static let userAgent = "LumiType/6.0"

    let key: String
    let endpoint: String
    let model: String

    public init(key: String, endpoint: String, model: String) {
        self.key = key
        self.endpoint = endpoint
        self.model = model
    }

    public var provider: Provider { .llm }

    public func makeRequest(text: String, source: String, target: String) throws -> URLRequest {
        guard !key.isEmpty else { throw EngineError("e_nokey_l") }
        guard let url = URL(string: endpoint) else {
            throw EngineError("e_conn", detail: "bad llm endpoint: \(endpoint)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(LlmClient.userAgent, forHTTPHeaderField: "User-Agent")

        let targetName = Languages.find(target)?.nameEn ?? target
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user",
                 "content": Prompt.translationInstruction(target: targetName, source: source) + "\n\n" + text]
            ],
            "temperature": 0.2,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }

    public func parse(_ data: Data) throws -> (text: String, detected: String?) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw EngineError("err_empty_l")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError("err_empty_l") }
        return (trimmed, nil)
    }
}

// MARK: - 工厂

public enum EngineFactory {
    public static func make(_ cfg: Config, provider: Provider? = nil, context: String = "") throws -> TranslationEngine {
        let p = provider ?? Provider(rawValue: cfg.provider) ?? .deepl
        switch p {
        case .deepl:
            return DeepLClient(key: cfg.effectiveDeepLKey,
                               baseUrl: cfg.baseUrl,
                               quality: cfg.qualityModel,
                               context: context)
        case .google:
            return GoogleClient(key: cfg.effectiveGoogleKey)
        case .llm:
            return LlmClient(key: cfg.effectiveLlmKey,
                             endpoint: cfg.llmEndpoint,
                             model: cfg.llmModel)
        }
    }
}

// MARK: - 翻译服务（缓存 + 计时 + 错误归一）

public final class TranslationService {

    public let config: Config
    public let cache: LruCache
    private let session: URLSession

    public init(config: Config, cache: LruCache? = nil, session: URLSession? = nil) {
        self.config = config.normalized()
        self.cache = cache ?? LruCache(
            capacity: self.config.cacheSize,
            path: Config.defaultDirectory().appendingPathComponent("transcache.json")
        )
        if let session {
            self.session = session
        } else {
            self.session = TranslationService.session(for: self.config)
        }
    }

    // MARK: - 连接复用（V6.2.0 的「长连接复用」）

    private static let sessionLock = NSLock()
    private static var cachedSession: URLSession?
    private static var cachedKey = ""

    /// 同一份代理/超时配置复用同一个 URLSession。
    /// 原版 V6.2.0 实测：`KeepAlive=false` 每次翻译都要重做 TCP+TLS，
    /// 多花 850–900 ms；改成复用后第二句起稳定在 500 ms 量级。
    public static func session(for cfg: Config) -> URLSession {
        let key = "\(cfg.proxyMode)|\(cfg.proxyServer)|\(cfg.timeoutMs)"
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let cached = cachedSession, cachedKey == key { return cached }

        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = Double(cfg.timeoutMs) / 1000.0
        c.timeoutIntervalForResource = Double(cfg.timeoutMs) / 1000.0 * 2
        c.connectionProxyDictionary = TranslationService.proxy(for: cfg)
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.httpMaximumConnectionsPerHost = 12
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        let made = URLSession(configuration: c)
        cachedSession = made
        cachedKey = key
        return made
    }

    static func proxy(for cfg: Config) -> [AnyHashable: Any]? {
        switch cfg.proxyMode {
        case "direct":
            // 空字典 = 显式禁用系统代理
            return [:]
        case "manual":
            let parts = cfg.proxyServer.split(separator: ":")
            guard parts.count >= 2, let port = Int(parts[1]) else { return nil }
            let host = String(parts[0])
            // 键名即 CFNetwork 代理字典的官方键
            return [
                "HTTPEnable": true,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": true,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        default:
            return nil
        }
    }

    /// 翻译入口。命中缓存时 `cached = true` 且不发请求。
    public func translate(
        _ rawText: String,
        provider: Provider? = nil,
        source: String? = nil,
        target: String? = nil,
        context: String? = nil
    ) async throws -> TranslationOutcome {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = provider ?? Provider(rawValue: config.provider) ?? .deepl
        let src = source ?? config.sourceLang
        let tgt = target ?? config.targetLang

        guard !text.isEmpty else {
            return TranslationOutcome(text: "", provider: p, latencyMs: 0, charCount: 0)
        }

        if let hit = cache.get(text, provider: p, source: src, target: tgt) {
            return TranslationOutcome(text: hit, provider: p, latencyMs: 0,
                                      charCount: text.count, cached: true)
        }

        let engine = try EngineFactory.make(config, provider: p, context: context ?? "")
        let request = try engine.makeRequest(text: text, source: src, target: tgt)

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let e as URLError {
            throw EngineError.from(urlError: e)
        } catch {
            throw EngineError("e_conn", detail: error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8)
            throw EngineError.from(status: http.statusCode, body: body)
        }

        let parsed = try engine.parse(data)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        cache.put(parsed.text, for: text, provider: p, source: src, target: tgt)
        return TranslationOutcome(text: parsed.text, provider: p, latencyMs: elapsed,
                                  charCount: text.count, cached: false,
                                  detectedSource: parsed.detected)
    }
}

// MARK: - HTML 反转义（Google 返回转义文本）

public enum Html {
    public static func unescape(_ s: String) -> String {
        var out = s
        let map = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "
        ]
        for (k, v) in map {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }
}
