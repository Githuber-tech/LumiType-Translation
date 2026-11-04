import XCTest
@testable import LumiTypeCore

// MARK: - 配置

final class ConfigTests: XCTestCase {

    func testMissingFieldsFallBackToDefaults() {
        let cfg = Config(dictionary: ["UiLang": "en"], filePath: "/tmp/x/settings.json")
        XCTAssertEqual(cfg.uiLang, "en")
        XCTAssertEqual(cfg.provider, "deepl")
        XCTAssertEqual(cfg.hotkeyToggle, "Alt+Y")
        XCTAssertEqual(cfg.glassOpacity, 85)
        XCTAssertEqual(cfg.llmEndpoint, "https://api.deepseek.com/v1/chat/completions")
    }

    func testWrongTypesAreTolerated() {
        let cfg = Config(dictionary: [
            "TimeoutMs": "30000",
            "GlassOpacity": NSNumber(value: 42),
            "AutoStart": "true",
            "FontScale": "1.25"
        ], filePath: "/tmp/x/settings.json")
        XCTAssertEqual(cfg.timeoutMs, 30_000)
        XCTAssertEqual(cfg.glassOpacity, 42)
        XCTAssertTrue(cfg.autoStart)
        XCTAssertEqual(cfg.fontScale, 1.25, accuracy: 0.0001)
    }

    /// v6.1.6 的核心修复：DeeplKey 为空时回退 ApiKey
    func testDeepLKeyFallsBackToLegacyApiKey() {
        var cfg = Config.defaults(filePath: "/tmp/x/settings.json")
        cfg.apiKey = "legacy:fx"
        cfg.deeplKey = ""
        XCTAssertEqual(cfg.effectiveDeepLKey, "legacy:fx")

        cfg.deeplKey = "new:fx"
        XCTAssertEqual(cfg.effectiveDeepLKey, "new:fx")
    }

    func testNormalizeClampsAndFixesEnums() {
        var cfg = Config.defaults(filePath: "/tmp/x/settings.json")
        cfg.glassOpacity = 5
        cfg.theme = "neon-cyber"
        cfg.provider = "bogus"
        cfg.uiLang = "fr"
        let n = cfg.normalized()
        XCTAssertEqual(n.glassOpacity, 15)
        XCTAssertEqual(n.theme, "paper-light")
        XCTAssertEqual(n.provider, "deepl")
        XCTAssertTrue(["zh", "en"].contains(n.uiLang))
    }

    func testSaveLoadRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitype-test-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("settings.json")
        var cfg = Config.defaults(filePath: file.path)
        cfg.glassOpacity = 33
        cfg.googleKey = "AIza-test"
        cfg.provider = "google"
        try cfg.save(to: file)

        let loaded = Config.load(from: file)
        XCTAssertEqual(loaded.glassOpacity, 33)
        XCTAssertEqual(loaded.googleKey, "AIza-test")
        XCTAssertEqual(loaded.provider, "google")
        try? FileManager.default.removeItem(at: dir)
    }

    func testCorruptFileIsQuarantined() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitype-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: file)

        let loaded = Config.load(from: file)
        XCTAssertEqual(loaded.glassOpacity, 85)   // 回落到默认

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.contains(".corrupt-") }, "损坏文件应被改名隔离")
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - 版本

final class VersionTests: XCTestCase {

    func testParse() {
        XCTAssertEqual(LumiVersion("6.1.6")?.description, "6.1.6")
        XCTAssertEqual(LumiVersion("V6.1.6")?.description, "6.1.6")
        XCTAssertEqual(LumiVersion("6.1")?.description, "6.1.0")
        XCTAssertNil(LumiVersion("abc"))
        XCTAssertNil(LumiVersion("6"))
    }

    func testBumpCarryRule() {
        XCTAssertEqual(LumiVersion("6.1.6")!.bumped(.patch).description, "6.1.7")
        XCTAssertEqual(LumiVersion("6.1.9")!.bumped(.patch).description, "6.2.0")
        XCTAssertEqual(LumiVersion("6.9.9")!.bumped(.minor).description, "7.0.0")
        XCTAssertEqual(LumiVersion("6.1.6")!.bumped(.minor).description, "6.2.0")
        XCTAssertEqual(LumiVersion("6.1.6")!.bumped(.major).description, "7.0.0")
    }

    func testValidate() {
        XCTAssertEqual(VersionCheck.check("6.1.6"), .ok)
        XCTAssertEqual(VersionCheck.check("6.1"), .fixed("6.1.0"))
        XCTAssertEqual(VersionCheck.check("x"), .invalid)
    }

    func testOrdering() {
        XCTAssertTrue(LumiVersion("6.1.5")! < LumiVersion("6.1.6")!)
        XCTAssertTrue(LumiVersion("6.2.0")! > LumiVersion("6.1.9")!)
    }
}

// MARK: - 缓存

final class LruCacheTests: XCTestCase {

    func testHitAndEvict() {
        let cache = LruCache(capacity: 2, path: nil)
        cache.put("a", for: "1", provider: .deepl, source: "en", target: "zh-CN")
        cache.put("b", for: "2", provider: .deepl, source: "en", target: "zh-CN")
        XCTAssertEqual(cache.get("1", provider: .deepl, source: "en", target: "zh-CN"), "a")

        // 访问过 1，所以淘汰的是 2
        cache.put("c", for: "3", provider: .deepl, source: "en", target: "zh-CN")
        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.get("1", provider: .deepl, source: "en", target: "zh-CN"))
        XCTAssertNil(cache.get("2", provider: .deepl, source: "en", target: "zh-CN"))
        XCTAssertNotNil(cache.get("3", provider: .deepl, source: "en", target: "zh-CN"))
    }

    func testProviderIsPartOfKey() {
        let cache = LruCache(capacity: 10, path: nil)
        cache.put("x", for: "hi", provider: .deepl, source: "en", target: "zh-CN")
        XCTAssertNil(cache.get("hi", provider: .google, source: "en", target: "zh-CN"))
    }

    func testPersistence() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitype-cache-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("transcache.json")

        let a = LruCache(capacity: 10, path: file)
        a.put("你好", for: "hello", provider: .deepl, source: "en", target: "zh-CN")
        a.flush()

        let b = LruCache(capacity: 10, path: file)
        XCTAssertEqual(b.get("hello", provider: .deepl, source: "en", target: "zh-CN"), "你好")
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - 引擎请求构造

final class EngineRequestTests: XCTestCase {

    func testDeepLRequestShape() throws {
        let client = DeepLClient(key: "k:fx", baseUrl: "", quality: true)
        let req = try client.makeRequest(text: "hello", source: "en", target: "zh-CN")

        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://api-free.deepl.com/v2/translate")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key k:fx")
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "LumiType/5.0")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["text"] as? [String], ["hello"])
        XCTAssertEqual(body["target_lang"] as? String, "ZH")
        XCTAssertEqual(body["source_lang"] as? String, "EN")
        XCTAssertEqual(body["split_sentences"] as? String, "nonewlines")
        XCTAssertEqual(body["preserve_formatting"] as? Bool, true)
        XCTAssertEqual(body["model_type"] as? String, "quality_optimized")
    }

    func testDeepLTargetMappings() throws {
        let client = DeepLClient(key: "k")
        let zhTW = try client.makeRequest(text: "x", source: "auto", target: "zh-TW")
        let body = try JSONSerialization.jsonObject(with: zhTW.httpBody!) as! [String: Any]
        XCTAssertEqual(body["target_lang"] as? String, "ZH-HANT")
        XCTAssertNil(body["source_lang"])   // auto 不传 source_lang
    }

    func testMissingKeyThrows() {
        let client = DeepLClient(key: "")
        XCTAssertThrowsError(try client.makeRequest(text: "x", source: "en", target: "zh-CN")) { error in
            XCTAssertEqual((error as? EngineError)?.code, "e_nokey_d")
        }
    }

    func testDeepLParse() throws {
        let data = #"{"translations":[{"detected_source_language":"EN","text":"你好"}]}"#.data(using: .utf8)!
        let out = try DeepLClient(key: "k").parse(data)
        XCTAssertEqual(out.text, "你好")
        XCTAssertEqual(out.detected, "EN")
    }

    func testGoogleParseUnescapes() throws {
        let data = #"{"data":{"translations":[{"translatedText":"Tom &amp; Jerry &#39;x&#39;"}]}}"#.data(using: .utf8)!
        let out = try GoogleClient(key: "k").parse(data)
        XCTAssertEqual(out.text, "Tom & Jerry 'x'")
    }

    func testLlmParse() throws {
        let data = #"{"choices":[{"message":{"role":"assistant","content":" bonjour "}}]}"#.data(using: .utf8)!
        let out = try LlmClient(key: "k", endpoint: "https://api.deepseek.com/v1/chat/completions", model: "deepseek-chat").parse(data)
        XCTAssertEqual(out.text, "bonjour")
    }
}

// MARK: - 端到端（桩服务器）

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, data) = handler(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class TranslationServiceTests: XCTestCase {

    private func makeService(cache: LruCache) -> TranslationService {
        let conf = URLSessionConfiguration.ephemeral
        conf.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: conf)

        var cfg = Config.defaults(filePath: "/tmp/x/settings.json")
        cfg.deeplKey = "k:fx"
        cfg.provider = "deepl"
        cfg.targetLang = "zh-CN"
        cfg.sourceLang = "en"
        return TranslationService(config: cfg, cache: cache, session: session)
    }

    func testTranslateThenCacheHit() async throws {
        var calls = 0
        StubProtocol.handler = { _ in
            calls += 1
            let body = #"{"translations":[{"detected_source_language":"EN","text":"你好，世界"}]}"#
            return (200, body.data(using: .utf8)!)
        }

        let cache = LruCache(capacity: 10, path: nil)
        let service = makeService(cache: cache)

        let first = try await service.translate("Hello, world")
        XCTAssertEqual(first.text, "你好，世界")
        XCTAssertFalse(first.cached)
        XCTAssertEqual(first.charCount, 12)

        let second = try await service.translate("Hello, world")
        XCTAssertEqual(second.text, "你好，世界")
        XCTAssertTrue(second.cached)
        XCTAssertEqual(calls, 1, "第二次应命中缓存，不再发请求")
    }

    func testHTTP403MapsToError() async {
        StubProtocol.handler = { _ in
            (403, #"{"message":"Forbidden"}"#.data(using: .utf8)!)
        }
        let service = makeService(cache: LruCache(capacity: 10, path: nil))
        do {
            _ = try await service.translate("hello")
            XCTFail("应当抛错")
        } catch let e as EngineError {
            XCTAssertEqual(e.code, "e_403")
            XCTAssertEqual(e.message("zh"), "访问被拒绝 (403)")
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    func testEmptyInputShortCircuits() async throws {
        let service = makeService(cache: LruCache(capacity: 10, path: nil))
        let out = try await service.translate("   ")
        XCTAssertEqual(out.text, "")
        XCTAssertEqual(out.charCount, 0)
    }
}

// MARK: - 文案与数据完整性

final class I18nTests: XCTestCase {

    func testEveryKeyHasBothLanguages() {
        for key in I18n.shared.keys {
            let zh = I18n.shared.t(key, "zh")
            let en = I18n.shared.t(key, "en")
            XCTAssertFalse(zh.isEmpty, "\(key) 中文为空")
            XCTAssertFalse(en.isEmpty, "\(key) 英文为空")
            XCTAssertNotEqual(zh, key, "\(key) 中文缺失")
            XCTAssertNotEqual(en, key, "\(key) 英文缺失")
        }
    }

    func testSpotCheckAgainstOriginal() {
        XCTAssertEqual(I18n.shared.t("tray_prefs", "zh"), "首选项 (&P)…")
        XCTAssertEqual(I18n.shared.t("st_done", "zh", ["120", "8"]), "120ms · 8 字")
        XCTAssertEqual(I18n.shared.t("st_cache", "en", ["8"]), "cached · 8 chars")
        XCTAssertEqual(I18n.shared.t("e_403", "en"), "Access denied (403)")
        XCTAssertEqual(I18n.shared.t("skin_light", "zh"), "浅色（白色磨砂玻璃）")
    }
}

final class ChangelogTests: XCTestCase {

    func testEntriesRecovered() {
        XCTAssertEqual(Changelog.all.count, 69)
        XCTAssertEqual(Changelog.all.first?.version, "6.1.6")
        XCTAssertEqual(Changelog.all.first?.title, "DeepL 请求没带 API Key 导致 403")
    }

    func testEnglishFallback() {
        let withEn = Changelog.all.first!
        XCTAssertEqual(Changelog.title(withEn, "en"),
                       "DeepL requests went out without the API key (403)")
        let noEn = Changelog.all.last!
        XCTAssertEqual(Changelog.title(noEn, "en"), noEn.title)
    }
}

final class PromptTests: XCTestCase {

    func testHasHanAndAutoPair() {
        XCTAssertTrue(Prompt.hasHan("你好"))
        XCTAssertFalse(Prompt.hasHan("hello"))
        XCTAssertEqual(Prompt.autoPair(for: "你好", uiLang: "zh").target, "en")
        XCTAssertEqual(Prompt.autoPair(for: "hello", uiLang: "zh").target, "zh-CN")
    }

    func testBuiltInTargets() {
        XCTAssertEqual(Prompt.builtInTargets.count, 10)
        XCTAssertEqual(Prompt.builtInTargets.first, "zh-CN")
    }
}
