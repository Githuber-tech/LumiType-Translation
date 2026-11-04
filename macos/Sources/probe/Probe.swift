import Cocoa
import ApplicationServices
import LumiTypeCore

/// 光标定位探测工具。
///
/// 目的：在写浮层之前，先量出「到底哪些 App 能给出插入符矩形」。
/// Windows 上的 `GetGUIThreadInfo` 一行就能拿到；macOS 只能走辅助功能（AX），
/// 而 AX 的实现质量在原生 Cocoa / Electron / 自绘 IM 之间差异极大。
///
/// 用法：
///   lumitype-probe --apps              列出运行中的 App 与 bundle id（不需要授权）
///   lumitype-probe --once              对当前前台 App 采样一次
///   lumitype-probe --duration 30       30 秒内持续采样，你手动在这些 App 之间切换
///   lumitype-probe --json              以 JSON 输出（便于归档对比）
@main
struct Probe {

    // MARK: - 参数

    struct Options {
        var once = false
        var listApps = false
        var json = false
        var duration: Double = 20
        var interval: Double = 0.1
    }

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--once": o.once = true
            case "--apps", "--list-apps": o.listApps = true
            case "--json": o.json = true
            case "--duration":
                if i + 1 < args.count, let v = Double(args[i + 1]) { o.duration = v; i += 1 }
            case "--interval":
                if i + 1 < args.count, let v = Double(args[i + 1]) { o.interval = v; i += 1 }
            case "--help", "-h":
                printHelp(); exit(0)
            default:
                break
            }
            i += 1
        }
        return o
    }

    static func main() {
        let opts = parse(Array(CommandLine.arguments.dropFirst()))

        if opts.listApps {
            listRunningApps(json: opts.json)
            return
        }

        guard ensureAccessibility() else { return }

        if opts.once {
            if let app = NSWorkspace.shared.frontmostApplication {
                let sample = probe(app: app)
                if opts.json {
                    print(json([sample]))
                } else {
                    printHeader()
                    printRow(sample, index: 1)
                }
            }
            return
        }

        watch(opts)
    }

    // MARK: - 权限

    /// 检查并申请辅助功能授权。没有它，AX 调用一律返回 kAXErrorAPIDisabled。
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted {
            FileHandle.standardError.write(Data("""
            
            ⚠️  未获得「辅助功能」权限，无法读取任何 App 的插入符位置。

            请到：系统设置 → 隐私与安全性 → 辅助功能
            把运行本程序的终端（或 iTerm / VS Code）打开开关，然后重新运行。

            注意：授权对象是「调用方进程」，不是本程序本身 ——
            从终端里跑就要授权终端；打包成 .app 后授权的是那个 .app。
            
            """.utf8))
        }
        return trusted
    }

    // MARK: - 运行中的 App

    static func listRunningApps(json: Bool) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        if json {
            let rows = apps.map { a -> [String: Any] in
                ["name": a.localizedName ?? "", "bundleId": a.bundleIdentifier ?? "", "pid": a.processIdentifier]
            }
            if let d = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: d, encoding: .utf8) {
                print(s)
            }
            return
        }

        print("运行中的 App（用于确定吸附白名单的 bundle id）\n")
        print(pad("PID", 7) + pad("BUNDLE ID", 30) + "NAME")
        print(String(repeating: "─", count: 78))
        for a in apps {
            print(pad(String(a.processIdentifier), 7)
                  + pad(a.bundleIdentifier ?? "-", 30)
                  + (a.localizedName ?? ""))
        }
        print("\n共 \(apps.count) 个。把目标 App 的 bundle id 记下来，写进白名单。")
    }

    // MARK: - 采样

    enum Tier: String {
        case axCaret        = "AX-光标"        // 拿到插入符矩形（理想）
        case axElementRect  = "AX-元素框"      // 只有元素边界，退而求其次
        case noTextElement  = "非文本元素"     // 焦点元素不是输入框
        case axError        = "AX-失败"        // AX 报错
        case noApp          = "无前台App"
    }

    struct Sample {
        var appName: String
        var bundleId: String
        var pid: pid_t
        var tier: Tier
        var rect: CGRect?
        var role: String?
        var subrole: String?
        var axError: AXError?
        var errorName: String
        var elapsedMs: Double
        var note: String
    }

    static func probe(app: NSRunningApplication) -> Sample {
        let started = CFAbsoluteTimeGetCurrent()
        let name = app.localizedName ?? "?"
        let bundle = app.bundleIdentifier ?? "?"

        func finish(_ tier: Tier, _ rect: CGRect?, _ role: String?,
                    _ subrole: String?, _ err: AXError?, _ note: String) -> Sample {
            Sample(appName: name, bundleId: bundle, pid: app.processIdentifier,
                   tier: tier, rect: rect, role: role, subrole: subrole,
                   axError: err, errorName: err.map(errorName) ?? "-",
                   elapsedMs: (CFAbsoluteTimeGetCurrent() - started) * 1000,
                   note: note)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // 1) 取焦点元素
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focusedRef else {
            return finish(.axError, nil, nil, nil, focusErr, "取不到焦点元素")
        }
        let element = focusedRef as! AXUIElement

        let role = stringAttr(element, kAXRoleAttribute)
        let subrole = stringAttr(element, kAXSubroleAttribute)

        // 2) 取选中范围（光标即为长度为 0 的选区）
        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)

        guard rangeErr == .success, let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            // 不是文本元素，或该元素不支持选区属性
            let tier: Tier = (role == "AXTextField" || role == "AXTextArea" || role == "AXWebArea")
                ? .axError : .noTextElement
            return finish(tier, nil, role, subrole, rangeErr, "无 AXSelectedTextRange")
        }

        let rangeValue = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return finish(.axError, nil, role, subrole, nil, "选区值无法解包为 CFRange")
        }

        // 3) 范围 → 屏幕矩形（关键一步）
        var boundsRef: CFTypeRef?
        let boundsErr = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef)

        if boundsErr == .success, let boundsRef,
           CFGetTypeID(boundsRef) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width >= 0, rect.height > 0 {
                return finish(.axCaret, rect, role, subrole, nil,
                              "插入符可用（offset=\(range.location), len=\(range.length)）")
            }
        }

        // 4) 降级：元素自身的边框（不是光标位置，但可用于「贴在输入框旁」）
        if let frame = elementFrame(element) {
            return finish(.axElementRect, frame, role, subrole, boundsErr,
                          "有选区但拿不到范围矩形，退回元素框")
        }

        return finish(.axError, nil, role, subrole, boundsErr, "BoundsForRange 不可用")
    }

    static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let value = ref as? String else { return nil }
        return value
    }

    // MARK: - 持续采样

    static func watch(_ opts: Options) {
        printHeader()
        let deadline = Date().addingTimeInterval(opts.duration)
        var samples: [Sample] = []
        var lastSignature: [String: String] = [:]
        var index = 0

        FileHandle.standardError.write(Data("""
        开始采样 \(Int(opts.duration)) 秒。请在这些 App 的输入框里点一下并打字：
          微信 / 飞书 / 钉钉 / Safari / 备忘录 / 备忘录以外的原生 App
        每个 App 停留 3～5 秒，切换时会自动记录。

        """.utf8))

        while Date() < deadline {
            if let app = NSWorkspace.shared.frontmostApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                let s = probe(app: app)
                let signature = "\(s.tier.rawValue)|\(s.rect.map { "\($0.origin.x),\($0.origin.y)" } ?? "-")"
                if lastSignature[s.bundleId] != signature {
                    lastSignature[s.bundleId] = signature
                    index += 1
                    samples.append(s)
                    printRow(s, index: index)
                }
            }
            Thread.sleep(forTimeInterval: opts.interval)
        }

        printSummary(samples, json: opts.json)
        if opts.json {
            print(json(samples))
        }
    }

    // MARK: - 输出

    /// 定宽填充。用字符数而非字节数，避免汉字把列冲歪；
    /// 不要用 String(format:) + "%s"，Swift String 作为 CVarArg 传 %s 会解引用野指针。
    static func pad(_ text: String, _ width: Int) -> String {
        let count = text.count
        guard count < width else { return text + " " }
        return text + String(repeating: " ", count: width - count)
    }

    static func printHeader() {
        print(pad("#", 4) + pad("APP", 16) + pad("层级", 14)
              + pad("BUNDLE ID", 24) + pad("插入符矩形", 18) + "备注")
        print(String(repeating: "─", count: 118))
    }

    static func printRow(_ s: Sample, index: Int) {
        let rect = s.rect.map {
            String(format: "%.0f,%.0f %.0fx%.0f", $0.origin.x, $0.origin.y, $0.width, $0.height)
        } ?? "-"
        let note = s.tier == .axError || s.tier == .noTextElement
            ? "\(s.note) (\(s.errorName))"
            : s.note
        print(pad(String(index), 4) + pad(s.appName, 16) + pad(s.tier.rawValue, 14)
              + pad(s.bundleId, 24) + pad(rect, 18) + note)
    }

    static func printSummary(_ samples: [Sample], json: Bool) {
        guard !json else { return }
        guard !samples.isEmpty else {
            print("\n没有采到样本。")
            return
        }

        // 每个 App 取「最好」的一次结果
        let rank: [Tier: Int] = [.axCaret: 4, .axElementRect: 3, .noTextElement: 2, .axError: 1, .noApp: 0]
        var best: [String: Sample] = [:]
        var counts: [String: [Tier: Int]] = [:]

        for s in samples {
            counts[s.bundleId, default: [:]][s.tier, default: 0] += 1
            if let cur = best[s.bundleId] {
                if (rank[s.tier] ?? 0) > (rank[cur.tier] ?? 0) { best[s.bundleId] = s }
            } else {
                best[s.bundleId] = s
            }
        }

        print("\n\n═══ 结论 ═══\n")
        let order = best.values.sorted { (rank[$0.tier] ?? 0) > (rank[$1.tier] ?? 0) }
        let viable = order.filter { $0.tier == .axCaret }
        let partial = order.filter { $0.tier == .axElementRect }
        let dead = order.filter { $0.tier == .noTextElement || $0.tier == .axError }

        print("可用（拿到插入符矩形）：\(viable.count) 个")
        for s in viable { print("  ✅ \(s.appName)  \(s.bundleId)  \(s.note)") }
        print("\n降级（只有元素框，浮层贴输入框而非光标）：\(partial.count) 个")
        for s in partial { print("  🟡 \(s.appName)  \(s.bundleId)  \(s.note)") }
        print("\n不可用（需回落到鼠标位置）：\(dead.count) 个")
        for s in dead { print("  ❌ \(s.appName)  \(s.bundleId)  \(s.tier.rawValue)  \(s.errorName)  \(s.note)") }

        print("\n各 App 采样分布：")
        for (bundle, dist) in counts.sorted(by: { $0.key < $1.key }) {
            let text = dist.sorted { $0.value > $1.value }
                .map { "\($0.key.rawValue)×\($0.value)" }
                .joined(separator: "  ")
            print("  \(bundle):  \(text)")
        }
        print("""

        说明：AX 坐标系原点在左上角（与 CGWindowList 一致），
        与 AppKit 的左下角原点不同，接入浮层时要翻转 y。
        """)
    }

    static func json(_ samples: [Sample]) -> String {
        let rows = samples.map { s -> [String: Any] in
            var d: [String: Any] = [
                "app": s.appName,
                "bundleId": s.bundleId,
                "pid": Int(s.pid),
                "tier": s.tier.rawValue,
                "axError": s.errorName,
                "elapsedMs": (s.elapsedMs * 100).rounded() / 100,
                "note": s.note
            ]
            if let r = s.rect {
                d["rect"] = ["x": r.origin.x, "y": r.origin.y, "w": r.width, "h": r.height]
            }
            if let role = s.role { d["role"] = role }
            if let sub = s.subrole { d["subrole"] = sub }
            return d
        }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    // MARK: - AX 错误码

    static func errorName(_ e: AXError) -> String {
        switch e {
        case .success: return "success"
        case .failure: return "kAXErrorFailure(-25200)"
        case .illegalArgument: return "kAXErrorIllegalArgument(-25201)"
        case .invalidUIElement: return "kAXErrorInvalidUIElement(-25202)"
        case .invalidUIElementObserver: return "kAXErrorInvalidUIElementObserver(-25203)"
        case .cannotComplete: return "kAXErrorCannotComplete(-25204)"
        case .attributeUnsupported: return "kAXErrorAttributeUnsupported(-25205)"
        case .actionUnsupported: return "kAXErrorActionUnsupported(-25206)"
        case .notificationUnsupported: return "kAXErrorNotificationUnsupported(-25207)"
        case .notImplemented: return "kAXErrorNotImplemented(-25208)"
        case .notificationAlreadyRegistered: return "kAXErrorNotificationAlreadyRegistered(-25209)"
        case .notificationNotRegistered: return "kAXErrorNotificationNotRegistered(-25210)"
        case .apiDisabled: return "kAXErrorAPIDisabled(-25211)"
        case .noValue: return "kAXErrorNoValue(-25212)"
        case .parameterizedAttributeUnsupported: return "kAXErrorParameterizedAttributeUnsupported(-25213)"
        case .notEnoughPrecision: return "kAXErrorNotEnoughPrecision(-25214)"
        @unknown default: return "AXError(\(e.rawValue))"
        }
    }

    static func printHelp() {
        print("""
        lumitype-probe — LumiType 光标定位探测

          --apps               列出运行中的 App 与 bundle id（不需要授权）
          --once               对当前前台 App 采样一次
          --duration <秒>      持续采样时长，默认 20
          --interval <秒>      采样间隔，默认 0.1
          --json               以 JSON 输出，便于归档对比
          --help               显示本帮助

        典型用法：
          1. lumitype-probe --apps          先看清目标 App 的 bundle id
          2. lumitype-probe --duration 40   然后切到各 App 的输入框里打字
          3. 把结论表发我，据此定降级链
        """)
    }
}
