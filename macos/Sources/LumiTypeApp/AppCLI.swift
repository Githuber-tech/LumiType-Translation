import AppKit
import LumiTypeCore

/// 命令行入口 —— 参数表与 Windows 版一致。
/// 有 CLI 参数时**不启动 GUI**，跑完即返回退出码；
/// 这也让 `open -a LumiType --args --translate ...` 之外的自动化好写。
enum AppCLI {

    /// 返回退出码；nil = 继续启动 GUI
    static func runIfNeeded(_ args: [String]) -> Int32? {
        guard let first = args.first else { return nil }
        switch first {
        case "--version":
            print("LumiType \(Product.versionText) (macOS)")
            return 0
        case "--help", "-h", "/?":
            printHelp()
            return 0
        case "--translate":
            return runTranslate(Array(args.dropFirst()))
        case "--bump":
            return runBump(Array(args.dropFirst()))
        case "--validate-version":
            return runValidate(Array(args.dropFirst()))
        case "--config":
            return printConfig()
        case "--make-icon":
            return makeIcon(Array(args.dropFirst()))
        case "--preview":
            return runPreview(Array(args.dropFirst()))
        case "--apply-update":
            FileHandle.standardError.write(Data("ERROR: --apply-update 由更新器在应用内调用，不单独执行\n".utf8))
            return 1
        case "--prefs", "--prefs-shot", "--restart-after", "--spawn", "--demo", "--demo-shot":
            return nil
        default:
            // 未知参数：交给 GUI（macOS 的 open 会带 -psn_ 等系统参数）
            if first.hasPrefix("-") {
                FileHandle.standardError.write(Data("ERROR: 未知参数：\(first)（用 --help 查看用法）\n".utf8))
                return 1
            }
            return nil
        }
    }

    // MARK: 翻译

    private static func runTranslate(_ rest: [String]) -> Int32 {
        var text: String?
        var target: String?
        var key: String?
        var baseUrl: String?
        var i = 0
        while i < rest.count {
            let arg = rest[i]
            func next() -> String? {
                guard i + 1 < rest.count else { return nil }
                i += 1
                return rest[i]
            }
            switch arg {
            case "--target": target = next()
            case "--api-key": key = next()
            case "--base-url": baseUrl = next()
            case "--no-stream": break
            default:
                text = text.map { $0 + " " + arg } ?? arg
            }
            i += 1
        }
        guard let input = text, !input.isEmpty else {
            return fail("--translate 需要一个文本参数")
        }

        var cfg = Config.load()
        // CLI 的 --translate 固定走 DeepL（与原版 `LumiType.Cli` 一致），
        // 否则配置文件里选了 LLM 又没有 Key 时，命令行会拿到 e_nokey_l。
        cfg.provider = Provider.deepl.rawValue
        if let key { cfg.deeplKey = key }
        if let baseUrl { cfg.baseUrl = baseUrl }
        if let target { cfg.targetLang = target }

        let semaphore = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task {
            defer { semaphore.signal() }
            do {
                let service = TranslationService(config: cfg)
                let source = LanguageResolver.deepLSource(cfg, text: input)
                let resolved = LanguageResolver.resolveTarget(cfg, text: input)
                let out = try await service.translate(input, source: source, target: resolved,
                                                      context: LanguageResolver.contextFor(target: resolved))
                print("--- result ---")
                print("text   : \(out.text)")
                print("chars  : \(out.charCount)")
                print("elapsed: \(out.latencyMs) ms")
                print("engine : \(out.provider.rawValue)\(out.cached ? " (cached)" : "")")
            } catch let error as EngineError {
                FileHandle.standardError.write(Data("ERROR: \(error.message(cfg.uiLang))\n".utf8))
                code = 1
            } catch {
                FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
                code = 1
            }
        }
        semaphore.wait()
        return code
    }

    // MARK: 版本

    private static func runBump(_ rest: [String]) -> Int32 {
        guard let raw = rest.first, let level = LumiVersion.Level(rawValue: raw) else {
            return fail("usage: --bump <major|minor|patch> [from]")
        }
        let fromRaw = rest.count > 1 ? rest[1] : Product.versionText
        guard let from = LumiVersion(fromRaw) else { return fail("bad version: \(fromRaw)") }
        print("current     \(from)")
        print("next \(raw.padding(toLength: 5, withPad: " ", startingAt: 0)) \(from.bumped(level))")
        return 0
    }

    private static func runValidate(_ rest: [String]) -> Int32 {
        guard let raw = rest.first else { return fail("usage: --validate-version <v>") }
        print("\(raw)\(VersionCheck.check(raw).description)")
        return 0
    }

    private static func printConfig() -> Int32 {
        let cfg = Config.load()
        print("file: \(cfg.filePath)")
        if let data = try? JSONSerialization.data(withJSONObject: cfg.normalized().dictionary(),
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return 0
    }

    // MARK: 图标 / 预览

    private static func makeIcon(_ rest: [String]) -> Int32 {
        let path = rest.first ?? "AppIcon.png"
        let size = CGFloat(Double(rest.count > 1 ? rest[1] : "1024") ?? 1024)
        if IconArt.writePNG(size: size, to: URL(fileURLWithPath: path)) {
            print("wrote \(path) (\(Int(size))px)")
            return 0
        }
        return fail("图标写入失败：\(path)")
    }

    private static func runPreview(_ rest: [String]) -> Int32 {
        var options = PreviewRenderer.Options()
        var output = "preview.png"
        var i = 0
        while i < rest.count {
            let arg = rest[i]
            func next() -> String? {
                guard i + 1 < rest.count else { return nil }
                i += 1
                return rest[i]
            }
            switch arg {
            case "--theme": options.theme = next() ?? options.theme
            case "--state": options.state = next() ?? options.state
            case "--scale": options.scale = CGFloat(Double(next() ?? "2") ?? 2)
            case "--opacity": options.opacity = Int(next() ?? "78") ?? 78
            case "--width": options.width = CGFloat(Double(next() ?? "375") ?? 375)
            case "--pinned": options.pinned = true
            case "--backdrop": options.backdrop = next() ?? options.backdrop
            case "--empty": options.state = "empty"
            default: output = arg
            }
            i += 1
        }
        guard let data = PreviewRenderer.renderPNG(options) else {
            return fail("离屏渲染失败")
        }
        do {
            try data.write(to: URL(fileURLWithPath: output))
            print("wrote \(output) state=\(options.state) theme=\(options.theme)")
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data(("ERROR: " + message + "\n").utf8))
        return 1
    }

    private static func printHelp() {
        print("""
        LumiType 灵译 \(Product.versionText) (macOS)

        USAGE
          LumiType                       启动菜单栏应用
          LumiType --translate <text> [--target LANG] [--api-key KEY] [--base-url URL] [--no-stream]
          LumiType --version
          LumiType --bump <major|minor|patch> [from]
          LumiType --validate-version <v>
          LumiType --config
          LumiType --prefs               启动并打开首选项
          LumiType --make-icon <out.png> [size]
          LumiType --preview <out.png> [--theme T] [--state S] [--scale N] [--pinned] [--empty]
          LumiType --help | -h | /?

        NOTES
          配置读取 ~/Library/Application Support/LumiType/settings.json
          字段名与 Windows 版 settings.json 完全一致，可直接拷贝。
        """)
    }
}
