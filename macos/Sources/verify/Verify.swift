import Foundation
import LumiTypeCore

/// 回归验证程序：`swift run verify`
///
/// 覆盖配置兼容、版本进位、LRU 淘汰、三个引擎的请求/解析、端到端翻译（桩服务器）、
/// 文案完整性与更新日志还原度。任一断言失败即返回非 0 退出码，可直接接 CI。
@main
struct Verify {

    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var checks = 0

    static func expect(_ condition: Bool, _ message: String,
                       file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        if !condition {
            failures += 1
            print("  FAIL  \(message)   (\(file):\(line))")
        }
    }

    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String,
                                          file: StaticString = #fileID, line: UInt = #line) {
        expect(a == b, "\(message) — 期望 \(b)，实际 \(a)", file: file, line: line)
    }

    static func section(_ name: String) { print("\n▸ \(name)") }

    static func main() async {
        testConfig()
        testVersion()
        testCache()
        testEngineRequests()
        await testTranslationService()
        testI18n()
        testChangelog()
        testPrompt()

        print("\n────────────────────────────")
        if failures == 0 {
            print("全部通过：\(checks) 项断言")
            exit(0)
        } else {
            print("失败 \(failures) / \(checks) 项断言")
            exit(1)
        }
    }

    // MARK: - 配置

    static func testConfig() {
        section("配置兼容")
        let c = Config(dictionary: ["UiLang": "en"], filePath: "/tmp/x/settings.json")
        expectEqual(c.uiLang, "en", "UiLang 被读取")
        expectEqual(c.provider, "deepl", "缺 Provider 用默认 deepl")
        expectEqual(c.hotkeyToggle, "Alt+Y", "默认热键")
        expectEqual(c.glassOpacity, 78, "默认浓度（src/Engine.cs）")
        expectEqual(c.llmEndpoint, "https://api.deepseek.com/v1/chat/completions", "LLM 默认端点")

        let tolerant = Config(dictionary: [
            "TimeoutMs": "30000",
            "GlassOpacity": NSNumber(value: 42),
            "AutoStart": "true",
            "FontScale": "1.25"
        ], filePath: "/tmp/x/settings.json")
        expectEqual(tolerant.timeoutMs, 30_000, "字符串数字被容错解析")
        expectEqual(tolerant.glassOpacity, 42, "NSNumber 被容错解析")
        expect(tolerant.autoStart, "字符串布尔被容错解析")

        var legacy = Config.defaults(filePath: "/tmp/x/settings.json")
        legacy.apiKey = "legacy:fx"
        legacy.deeplKey = ""
        expectEqual(legacy.effectiveDeepLKey, "legacy:fx", "v6.1.6：DeeplKey 空时回退 ApiKey")
        legacy.deeplKey = "new:fx"
        expectEqual(legacy.effectiveDeepLKey, "new:fx", "DeeplKey 优先")

        var clamped = Config.defaults(filePath: "/tmp/x/settings.json")
        clamped.glassOpacity = 5
        clamped.theme = "neon-cyber"
        clamped.provider = "bogus"
        let n = clamped.normalized()
        expectEqual(n.glassOpacity, 15, "浓度下限夹到 15")
        expectEqual(n.theme, "glass-dark", "未知皮肤回退到默认 skin")
        expectEqual(n.provider, "deepl", "未知引擎回退")

        // 落盘 → 读回
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitype-verify-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("settings.json")
        var rt = Config.defaults(filePath: file.path)
        rt.glassOpacity = 33
        rt.googleKey = "AIza-test"
        do {
            try rt.save(to: file)
            let loaded = Config.load(from: file)
            expectEqual(loaded.glassOpacity, 33, "保存后读回浓度一致")
            expectEqual(loaded.googleKey, "AIza-test", "保存后读回 Key 一致")
        } catch {
            expect(false, "保存配置失败：\(error)")
        }

        // 损坏文件隔离
        let badFile = dir.appendingPathComponent("bad.json")
        try? Data("{ not json".utf8).write(to: badFile)
        let recovered = Config.load(from: badFile)
        expectEqual(recovered.glassOpacity, 78, "损坏配置回落默认值")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        expect(names.contains { $0.contains("corrupt-") }, "损坏文件被改名隔离")
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 版本

    static func testVersion() {
        section("版本号规则")
        expectEqual(LumiVersion("6.1.6")?.description, "6.1.6", "解析 6.1.6")
        expectEqual(LumiVersion("V6.1.6")?.description, "6.1.6", "解析带 V 前缀")
        expectEqual(LumiVersion("6.1")?.description, "6.1.0", "缺段补 0")
        expect(LumiVersion("abc") == nil, "非法版本返回 nil")

        expectEqual(LumiVersion("6.1.6")!.bumped(.patch).description, "6.1.7", "patch +1")
        expectEqual(LumiVersion("6.1.9")!.bumped(.patch).description, "6.2.0", "patch 9 进位到 minor")
        expectEqual(LumiVersion("6.9.9")!.bumped(.minor).description, "7.0.0", "minor 9 进位到 major")
        expectEqual(LumiVersion("6.1.6")!.bumped(.major).description, "7.0.0", "major +1 清零低位")

        expectEqual(VersionCheck.check("6.1.6"), .ok, "合法版本")
        expectEqual(VersionCheck.check("6.1"), .fixed("6.1.0"), "两段版本给出修正")
        expectEqual(VersionCheck.check("x"), .invalid, "非法版本判为 invalid")
        expect(LumiVersion("6.1.5")! < LumiVersion("6.1.6")!, "版本可比较")
    }

    // MARK: - 缓存

    static func testCache() {
        section("LRU 缓存")
        let cache = LruCache(capacity: 2, path: nil)
        cache.put("a", for: "1", provider: .deepl, source: "en", target: "zh-CN")
        cache.put("b", for: "2", provider: .deepl, source: "en", target: "zh-CN")
        expectEqual(cache.get("1", provider: .deepl, source: "en", target: "zh-CN"), "a", "命中")

        cache.put("c", for: "3", provider: .deepl, source: "en", target: "zh-CN")
        expectEqual(cache.count, 2, "超过上限即淘汰")
        expect(cache.get("1", provider: .deepl, source: "en", target: "zh-CN") != nil, "最近使用的不被淘汰")
        expect(cache.get("2", provider: .deepl, source: "en", target: "zh-CN") == nil, "最久未用的被淘汰")

        expect(cache.get("1", provider: .google, source: "en", target: "zh-CN") == nil, "引擎参与缓存键")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitype-cache-\(UUID().uuidString)")
        let f = dir.appendingPathComponent("transcache.json")
        let a = LruCache(capacity: 10, path: f)
        a.put("你好", for: "hello", provider: .deepl, source: "en", target: "zh-CN")
        a.flush()
        let b = LruCache(capacity: 10, path: f)
        expectEqual(b.get("hello", provider: .deepl, source: "en", target: "zh-CN"), "你好", "缓存可持久化")
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 引擎请求

    static func testEngineRequests() {
        section("引擎请求构造")
        do {
            let req = try DeepLClient(key: "k:fx", baseUrl: "", quality: true)
                .makeRequest(text: "hello", source: "en", target: "zh-CN")
            expectEqual(req.httpMethod ?? "", "POST", "DeepL 用 POST")
            expectEqual(req.url?.absoluteString ?? "", "https://api-free.deepl.com/v2/translate", "DeepL 端点")
            expectEqual(req.value(forHTTPHeaderField: "Authorization") ?? "", "DeepL-Auth-Key k:fx", "DeepL 认证头")
            expectEqual(req.value(forHTTPHeaderField: "User-Agent") ?? "", "LumiType/5.0", "DeepL UA")

            let body = (try JSONSerialization.jsonObject(with: req.httpBody!)) as! [String: Any]
            expectEqual(body["text"] as? [String], ["hello"], "body.text")
            expectEqual(body["target_lang"] as? String, "ZH", "target_lang")
            expectEqual(body["source_lang"] as? String, "EN", "source_lang")
            expectEqual(body["split_sentences"] as? String, "nonewlines", "split_sentences")
            expectEqual(body["preserve_formatting"] as? Bool, true, "preserve_formatting")
            expectEqual(body["model_type"] as? String, "quality_optimized", "精译参数")
        } catch {
            expect(false, "DeepL 请求构造抛错：\(error)")
        }

        // zh-TW → ZH-HANT，auto 不传 source_lang
        do {
            let req = try DeepLClient(key: "k").makeRequest(text: "x", source: "auto", target: "zh-TW")
            let body = (try JSONSerialization.jsonObject(with: req.httpBody!)) as! [String: Any]
            expectEqual(body["target_lang"] as? String, "ZH-HANT", "繁中映射 ZH-HANT")
            expect(body["source_lang"] == nil, "auto 时不传 source_lang")
        } catch {
            expect(false, "繁中请求构造抛错：\(error)")
        }

        // 缺 Key
        do {
            _ = try DeepLClient(key: "").makeRequest(text: "x", source: "en", target: "zh-CN")
            expect(false, "缺 Key 应当抛错")
        } catch let e as EngineError {
            expectEqual(e.code, "e_nokey_d", "缺 Key 错误码")
        } catch {
            expect(false, "缺 Key 错误类型不符")
        }

        // 解析
        do {
            let d = #"{"translations":[{"detected_source_language":"EN","text":"你好"}]}"#.data(using: .utf8)!
            let out = try DeepLClient(key: "k").parse(d)
            expectEqual(out.text, "你好", "DeepL 解析译文")
            expectEqual(out.detected ?? "", "EN", "DeepL 解析识别语言")
        } catch {
            expect(false, "DeepL 解析失败：\(error)")
        }
        do {
            let d = #"{"data":{"translations":[{"translatedText":"Tom &amp; Jerry &#39;x&#39;"}]}}"#.data(using: .utf8)!
            let out = try GoogleClient(key: "k").parse(d)
            expectEqual(out.text, "Tom & Jerry 'x'", "Google HTML 反转义")
        } catch {
            expect(false, "Google 解析失败：\(error)")
        }
        do {
            let d = #"{"choices":[{"message":{"role":"assistant","content":" bonjour "}}]}"#.data(using: .utf8)!
            let out = try LlmClient(key: "k", endpoint: "https://x/y", model: "m").parse(d)
            expectEqual(out.text, "bonjour", "LLM 解析并去空白")
        } catch {
            expect(false, "LLM 解析失败：\(error)")
        }
    }

    // MARK: - 端到端

    static func testTranslationService() async {
        section("端到端翻译（桩服务器）")

        func makeService(cache: LruCache) -> TranslationService {
            let conf = URLSessionConfiguration.ephemeral
            conf.protocolClasses = [StubProtocol.self]
            let session = URLSession(configuration: conf)
            var cfg = Config.defaults(filePath: "/tmp/x/settings.json")
            cfg.deeplKey = "k:fx"
            cfg.provider = "deepl"
            cfg.sourceLang = "en"
            cfg.targetLang = "zh-CN"
            return TranslationService(config: cfg, cache: cache, session: session)
        }

        // 成功 + 缓存命中
        nonisolated(unsafe) var calls = 0
        StubProtocol.handler = { _ in
            calls += 1
            let body = #"{"translations":[{"detected_source_language":"EN","text":"你好，世界"}]}"#
            return (200, body.data(using: .utf8)!)
        }
        let cache = LruCache(capacity: 10, path: nil)
        let service = makeService(cache: cache)
        do {
            let first = try await service.translate("Hello, world")
            expectEqual(first.text, "你好，世界", "译文正确")
            expect(!first.cached, "首次不是缓存")
            expectEqual(first.charCount, 12, "原文字数统计")

            let second = try await service.translate("Hello, world")
            expect(second.cached, "第二次命中缓存")
            expectEqual(calls, 1, "命中缓存后不再发请求")
        } catch {
            expect(false, "翻译失败：\(error)")
        }

        // 403 → e_403
        StubProtocol.handler = { _ in
            (403, #"{"message":"Forbidden"}"#.data(using: .utf8)!)
        }
        do {
            _ = try await makeService(cache: LruCache(capacity: 10, path: nil)).translate("hello")
            expect(false, "403 应当抛错")
        } catch let e as EngineError {
            expectEqual(e.code, "e_403", "403 映射到 e_403")
            expectEqual(e.message("zh"), "访问被拒绝 (403)", "403 中文文案")
        } catch {
            expect(false, "403 错误类型不符")
        }

        // 空输入短路
        do {
            let out = try await makeService(cache: LruCache(capacity: 10, path: nil)).translate("   ")
            expectEqual(out.text, "", "空输入返回空")
            expectEqual(out.charCount, 0, "空输入字数为 0")
        } catch {
            expect(false, "空输入不该抛错：\(error)")
        }
    }

    // MARK: - 文案

    static func testI18n() {
        section("文案完整性")
        var missing: [String] = []
        for key in I18n.shared.keys {
            let zh = I18n.shared.t(key, "zh")
            let en = I18n.shared.t(key, "en")
            if zh.isEmpty || en.isEmpty || zh == key || en == key { missing.append(key) }
        }
        expect(missing.isEmpty, "所有键都有中英文案，缺失：\(missing)")

        expectEqual(I18n.shared.t("tray_prefs", "zh"), "首选项 (&P)…", "托盘文案一致")
        expectEqual(I18n.shared.t("st_done", "zh", ["120", "8"]), "120ms · 8 字", "状态行占位替换")
        expectEqual(I18n.shared.t("st_cache", "en", ["8"]), "cached · 8 chars", "缓存状态英文")
        expectEqual(I18n.shared.t("e_403", "en"), "Access denied (403)", "403 英文")
        expectEqual(I18n.shared.t("skin_light", "zh"), "浅色（白色磨砂玻璃）", "皮肤文案")
        expectEqual(I18n.shared.t("hints_free", "zh"),
                    "点输入框打中文    Enter 输出译文    Ctrl+Enter 输出原文    Esc 关闭浮层",
                    "提示行文案")
    }

    // MARK: - 更新日志

    static func testChangelog() {
        section("更新日志还原")
        expectEqual(Changelog.all.count, 71, "71 条 = macOS 2.0.0 + 70 条 Windows 历史")
        expectEqual(Changelog.all.first?.version ?? "", "2.0.0", "首条为 macOS 2.0.0")
        expectEqual(Changelog.all.first?.title ?? "", "macOS 原生版首发：菜单栏浮层、吸附、四页首选项、通用二进制", "首条标题")
        if let first = Changelog.all.first {
            expectEqual(Changelog.title(first, "en"),
                        "First macOS release: menu-bar overlay, snapping, four preference pages, a universal binary",
                        "英文标题")
        }
        if let last = Changelog.all.last {
            expectEqual(Changelog.title(last, "en"), last.title, "无英文时回退中文")
        }
        let withEn = Changelog.all.filter { $0.titleEn != nil }.count
        expectEqual(withEn, 57, "57 条带英文（macOS 条目 + 56 条原版）")
        expectEqual(Changelog.kindLabel("大更新", "en"), "Major update", "级别文案映射")
    }

    // MARK: - 提示词

    static func testPrompt() {
        section("语言方向推断")
        expect(Prompt.hasHan("你好"), "汉字识别")
        expect(!Prompt.hasHan("hello"), "非汉字识别")
        expectEqual(Prompt.autoPair(for: "你好", uiLang: "zh").target, "en", "中文输入→译英文")
        expectEqual(Prompt.autoPair(for: "hello", uiLang: "zh").target, "zh-CN", "英文输入→译中文")
        expectEqual(Prompt.builtInTargets.count, 10, "10 种内置语言")
        expectEqual(Prompt.builtInTargets.first ?? "", "zh-CN", "首个语言")
    }
}

// MARK: - 桩服务器

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
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
