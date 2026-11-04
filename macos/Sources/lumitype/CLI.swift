import Foundation
import LumiTypeCore

/// 命令行入口，对应原版 `LumiType.Cli`。
///
/// 参数表与 Windows 版保持一致（`--translate` / `--version` / `--bump` /
/// `--validate-version` 等）。图标相关与 `--preview` 渲染参数属于 Windows GDI+
/// 专有路径，Mac 版在 UI 阶段以等价能力实现，此处先给出明确提示而非静默忽略。
@main
struct CLI {

    static let version = Product.version

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first else {
            printHelp()
            exit(0)
        }

        switch first {
        case "--version":
            print("LumiType \(version)")
        case "--help", "-h", "/?":
            printHelp()
        case "--translate":
            await runTranslate(Array(args.dropFirst()))
        case "--bump":
            runBump(Array(args.dropFirst()))
        case "--validate-version":
            runValidate(Array(args.dropFirst()))
        case "--config":
            printConfig()
        case "--make-icon", "--icon-sheet":
            fail("该参数依赖 Windows GDI+ 图标生成路径，macOS 版由 UI 阶段以 SF Symbols/PNG 资源替代（尚未实现）")
        case "--preview":
            fail("--preview 依赖 WinForms 离屏渲染，macOS 版待 UI 阶段提供等价的截图子命令")
        default:
            fail("未知参数：\(first)（用 --help 查看用法）")
        }
    }

    // MARK: - 翻译

    static func runTranslate(_ rest: [String]) async {
        var text: String?
        var target: String?
        var apiKey: String?
        var baseUrl: String?
        var i = 0
        while i < rest.count {
            let a = rest[i]
            func next() -> String? {
                guard i + 1 < rest.count else { return nil }
                i += 1
                return rest[i]
            }
            switch a {
            case "--target": target = next()
            case "--api-key": apiKey = next()
            case "--base-url": baseUrl = next()
            case "--no-stream": break   // 非流式：Swift 版默认即非流式
            default:
                if let current = text { text = current + " " + a } else { text = a }
            }
            i += 1
        }

        guard let input = text, !input.isEmpty else {
            fail("--translate 需要一个文本参数")
        }

        var cfg = Config.load()
        if let apiKey { cfg.deeplKey = apiKey; cfg.apiKey = apiKey }
        if let baseUrl { cfg.baseUrl = baseUrl }
        if let target { cfg.targetLang = target }
        cfg.provider = Provider.deepl.rawValue

        let service = TranslationService(config: cfg)
        let started = Date()
        do {
            let out = try await service.translate(input)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            print("--- result ---")
            print("text   : \(out.text)")
            print("chars  : \(input.count)")
            print("elapsed: \(elapsed) ms")
            print("engine : \(out.provider.rawValue)\(out.cached ? " (cached)" : "")")
            if let detected = out.detectedSource {
                print("source : \(detected)")
            }
        } catch let e as EngineError {
            FileHandle.standardError.write(Data("ERROR: \(e.message(cfg.uiLang))\n".utf8))
            if let d = e.detail { FileHandle.standardError.write(Data("detail: \(d)\n".utf8)) }
            exit(1)
        } catch {
            fail("\(error)")
        }
    }

    // MARK: - 版本

    static func runBump(_ rest: [String]) {
        guard let levelRaw = rest.first, let level = LumiVersion.Level(rawValue: levelRaw) else {
            fail("usage: --bump <major|minor|patch> [from]")
        }
        let fromRaw = rest.count > 1 ? rest[1] : version.description
        guard let from = LumiVersion(fromRaw) else {
            fail("bad version: \(fromRaw)")
        }
        print("current     \(from)")
        print("next \(levelRaw.padding(toLength: 5, withPad: " ", startingAt: 0)) \(from.bumped(level))")
    }

    static func runValidate(_ rest: [String]) {
        guard let raw = rest.first else {
            fail("usage: --validate-version <v>")
        }
        print("\(raw)\(VersionCheck.check(raw).description)")
    }

    // MARK: - 配置

    static func printConfig() {
        let cfg = Config.load()
        print("file: \(cfg.filePath)")
        let data = try? JSONSerialization.data(
            withJSONObject: cfg.normalized().dictionary(),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if let data, let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }

    // MARK: - 帮助

    static func printHelp() {
        print("""
        LumiType 灵译 \(version)

        USAGE
          lumitype --translate <text> [--target LANG] [--api-key KEY] [--base-url URL] [--no-stream]
          lumitype --version
          lumitype --bump <major|minor|patch> [from]
          lumitype --validate-version <v>
          lumitype --config
          lumitype --help | -h | /?

        NOTES
          配置读取 ~/Library/Application Support/LumiType/settings.json
          未指定 --api-key 时使用配置文件里的 DeeplKey（为空回退 ApiKey）
        """)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("ERROR: " + message + "\n").utf8))
        exit(1)
    }
}
