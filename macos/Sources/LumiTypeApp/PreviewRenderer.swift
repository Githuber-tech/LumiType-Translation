import AppKit
import LumiTypeCore

/// 离屏渲染卡片。
///
/// 对应原版的 `--preview`：Windows 版用 GDI+ 离屏出图做设计验收，
/// Mac 版用 `cacheDisplay(in:to:)` —— 这样不需要窗口服务器也能出 PNG，
/// 便于在 CI / 无头环境里比对视觉回归。
enum PreviewRenderer {

    struct Options {
        var state = "done"          // done | streaming | waiting | error | empty
        var theme = "glass-dark"
        var scale: CGFloat = 2
        var pinned = false
        var opacity = 78
        var width: CGFloat = 375
        var backdrop = "dark"          // dark | light | none
    }

    static func makeModel(_ options: Options) -> CardModel {
        var m = CardModel()
        m.theme = Skin.from(options.theme)
        m.glassOpacity = options.opacity
        m.engineLabel = "DeepL"
        m.sourceLabel = "简体中文"
        m.targetLabel = "English"
        m.pinned = options.pinned
        if options.pinned { m.snapLabel = "已吸附 · 微信" }

        switch options.state {
        case "empty":
            m.source = ""
            m.status = ""
        case "waiting":
            m.source = "我们明天下午三点开会，请提前准备报价单。"
            m.waiting = true
            m.status = "翻译中"
        case "streaming":
            m.source = "我们明天下午三点开会，请提前准备报价单。"
            m.result = "Let's meet at 3 p.m. tomorrow"
            m.resultFor = m.source
            m.streaming = true
            m.status = "1240ms · 28 字"
            m.statusTone = .ok
        case "error":
            m.source = "hello world"
            m.error = true
            m.status = "失败"
            m.statusTone = .err
            m.warning = "API Key 无效或已过期 (401)"
        default:
            m.source = "我们明天下午三点开会，请提前准备报价单。"
            m.result = "Let's meet at 3 p.m. tomorrow — please have the quotation ready beforehand."
            m.resultFor = m.source
            m.status = "4516ms · 28 字"
            m.statusTone = .ok
        }
        m.hints = options.pinned
            ? I18n.shared.t("hints_pinned", "zh")
            : I18n.shared.t("hints_model", "zh")
        m.inputLines = 1
        m.widthOverride = options.width
        return m
    }

    /// 预览底板：Windows 版的 `--backdrop` 用来检查玻璃在深浅桌面上的可读性
    private final class BackdropView: NSView {
        var color: NSColor = .black
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            bounds.fill()
        }
    }

    /// 渲染成 PNG 数据
    static func renderPNG(_ options: Options) -> Data? {
        let model = makeModel(options)
        let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.maxWidth = 600
        view.maxHeight = 900
        view.model = model

        let size = NSSize(width: view.layout.winW, height: view.layout.winH)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let container = BackdropView(frame: NSRect(origin: .zero, size: size))
        switch options.backdrop {
        case "light": container.color = NSColor(srgbRed: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        case "none": container.color = .clear
        default: container.color = NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1)
        }
        container.addSubview(view)

        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return nil }
        container.cacheDisplay(in: container.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
