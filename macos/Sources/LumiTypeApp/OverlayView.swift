import AppKit
import LumiTypeCore

/// 卡片视图。整张卡片是手绘的 —— 移植自 `CardRenderer.cs` 的 `Draw()` 系列，
/// 绘制顺序、圆角、渐变、发光层数、内描边全部照搬。
final class OverlayView: NSView {

    enum Action {
        case close
        case unpin
        case note
        case swap
    }

    var onAction: ((Action) -> Void)?
    var onTextChange: ((String) -> Void)?
    var onEdited: (() -> Void)?
    var onSizeChange: ((CGSize) -> Void)?
    var onDragBegin: (() -> Void)?
    var onDragMove: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?
    var onCommitText: ((String, Bool) -> Void)?   // (text, isOriginal)
    var onKey: ((InputTextView.Command) -> Void)?

    var maxWidth: CGFloat = 600
    var maxHeight: CGFloat = 900

    private(set) var layout = CardLayout()
    private(set) var palette = Palette.dark()
    private(set) var input = InputTextView()

    /// 呼吸动画相位（吸附预览、思考圆点、流式光标共用）
    var pulse: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var model = CardModel() {
        didSet {
            if input.string != model.source && !isEditing {
                input.string = model.source
            }
            applyInputStyle()
            relayout()
            needsDisplay = true
        }
    }

    /// 用户正在输入时不要用外部值覆盖输入框
    private var isEditing = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear

        input.frame = .zero
        input.isRichText = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.isVerticallyResizable = false
        input.isHorizontallyResizable = false
        input.textContainerInset = .zero
        input.textContainer?.lineFragmentPadding = 0
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.heightTracksTextView = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.isContinuousSpellCheckingEnabled = false
        input.onEdited = { [weak self] in
            guard let self else { return }
            self.isEditing = true
            self.onTextChange?(self.input.string)
            self.onEdited?()
        }
        input.onCommand = { [weak self] cmd in
            self?.onKey?(cmd)
        }
        addSubview(input)

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - 布局

    func relayout() {
        layout = CardLayout.make(model, maxWidth: maxWidth, maxHeight: maxHeight)
        input.frame = layout.inputRect
        updateTextContainer()
        let size = CGSize(width: layout.winW, height: layout.winH)
        if frame.size != size { onSizeChange?(size) }
        needsDisplay = true
    }

    private func updateTextContainer() {
        let h = max(layout.fsSrc * 1.34, layout.inputRect.height)
        input.textContainer?.containerSize = NSSize(width: layout.inputRect.width, height: h)
    }

    private func applyInputStyle() {
        let p = Palette.make(model.theme)
        palette = p
        input.font = Typo.font(layout.fsSrc == 0 ? 12 : layout.fsSrc)
        input.textColor = p.text
        input.insertionPointColor = p.accent
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = layout.fsSrc * 1.34
        style.maximumLineHeight = layout.fsSrc * 1.34
        input.defaultParagraphStyle = style
        input.typingAttributes = [
            .font: Typo.font(layout.fsSrc == 0 ? 12 : layout.fsSrc),
            .foregroundColor: p.text,
            .paragraphStyle: style
        ]
    }

    func focusInput() {
        window?.makeFirstResponder(input)
        input.setSelectedRange(NSRange(location: input.string.count, length: 0))
        isEditing = true
    }

    func setText(_ text: String) {
        input.string = text
        isEditing = false
    }

    var inputString: String { input.string }

    // MARK: - 鼠标

    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var resizing = false
    private var resizeStartWidth: CGFloat = 0

    private var cardRect: CGRect { layout.cardRect }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if layout.closeRect.contains(p) { onAction?(.close); return }
        if model.pinned && layout.unpinRect.contains(p) { onAction?(.unpin); return }
        if layout.noteRect.contains(p) { onAction?(.note); return }
        if layout.swapRect.contains(p) { onAction?(.swap); return }

        // 双击边缘 → 宽度复位（V4.6.0）
        if event.clickCount == 2, abs(p.x - cardRect.minX) < 6 || abs(p.x - cardRect.maxX) < 6 {
            onWidthChange?(0)
            return
        }
        // 边缘拉伸：只在未吸附时可用
        if !model.pinned, abs(p.x - cardRect.minX) < 5 || abs(p.x - cardRect.maxX) < 5 {
            resizing = true
            resizeStartWidth = model.widthOverride > 0 ? model.widthOverride : layout.cardW
            dragStartMouse = NSEvent.mouseLocation
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        onDragBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        if resizing {
            let dx = now.x - dragStartMouse.x
            let leftEdge = dragStartMouse.x < (window?.frame.midX ?? 0)
            let width = max(300, resizeStartWidth + (leftEdge ? -dx * 2 : dx * 2))
            onWidthChange?(width)
            return
        }
        guard let window else { return }
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
        onDragMove?()
    }

    override func mouseUp(with event: NSEvent) {
        if resizing {
            resizing = false
            return
        }
        onDragEnd?()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let close = layout.closeRect.contains(p)
        let unpin = model.pinned && layout.unpinRect.contains(p)
        let note = layout.noteRect.contains(p)
        let swap = layout.swapRect.contains(p)
        if close != model.closeHover || unpin != model.unpinHover
            || note != model.noteHover || swap != model.swapHover {
            model.closeHover = close
            model.unpinHover = unpin
            model.noteHover = note
            model.swapHover = swap
            needsDisplay = true
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let p = palette
        let L = layout
        let card = L.cardRect

        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        drawGlow(ctx, card: card, radius: L.radius, shadow: p.shadow)
        drawBody(ctx, card: card, radius: L.radius, palette: p, opacity: model.glassOpacity)
        drawRail(ctx, card: card, layout: L, palette: p)

        let innerX = card.minX + L.padX + L.railW
        if L.showPills { drawPills(ctx, innerX: innerX, layout: L, palette: p) }
        if L.showSrc { drawInputPanel(ctx, layout: L, card: card, palette: p) }
        if L.showDivider {
            ctx.setFillColor(p.divider.cgColor)
            ctx.fill(CGRect(x: innerX, y: card.minY + L.divY,
                            width: card.maxX - L.padX - innerX, height: 1))
        }
        if L.showMain { drawMain(ctx, card: card, layout: L, palette: p) }
        if L.showHints { drawHints(ctx, card: card, layout: L, palette: p) }
        drawNoteButton(ctx, card: card, layout: L, palette: p)
        if model.pinned { drawUnpinButton(ctx, card: card, layout: L, palette: p) }
        drawCloseButton(ctx, card: card, layout: L, palette: p)
        if model.snapPreview { drawSnapPreview(ctx, card: card, layout: L, palette: p) }
    }

    private func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect,
               cornerWidth: min(radius, rect.width / 2),
               cornerHeight: min(radius, rect.height / 2),
               transform: nil)
    }

    private func verticalGradient(_ ctx: CGContext, _ rect: CGRect,
                                  _ from: NSColor, _ to: NSColor) {
        let colors = [from.cgColor, to.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [])
        ctx.restoreGState()
    }

    /// 外发光：8 层递增的圆角矩形，逐层衰减（`DrawGlow`）
    private func drawGlow(_ ctx: CGContext, card: CGRect, radius: CGFloat, shadow: NSColor) {
        ctx.saveGState()
        let clip = CGMutablePath()
        clip.addRect(bounds.insetBy(dx: -40, dy: -40))
        clip.addPath(roundedPath(card, radius))
        ctx.addPath(clip)
        ctx.clip(using: .evenOdd)

        let layers = 8
        for i in stride(from: layers, through: 1, by: -1) {
            let infl = CGFloat(i) * 1.15
            let t = CGFloat(i) / CGFloat(layers)
            let a = shadow.alphaComponent * t * t * 0.34
            if a <= 0 { continue }
            let r = card.insetBy(dx: -infl, dy: -infl)
            ctx.setFillColor(shadow.withAlphaComponent(a).cgColor)
            ctx.addPath(roundedPath(r, radius + infl))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private func drawBody(_ ctx: CGContext, card: CGRect, radius: CGFloat,
                          palette p: Palette, opacity: Int) {
        let op = CGFloat(min(100, max(15, opacity))) / 100.0
        let skinA = 0.10 + 0.90 * op

        ctx.saveGState()
        ctx.addPath(roundedPath(card, radius))
        ctx.clip()
        verticalGradient(ctx, card,
                         p.bgTop.withAlphaComponent(skinA),
                         p.bgBottom.withAlphaComponent(skinA))
        // 顶部高光
        let sheenRect = CGRect(x: card.minX, y: card.minY, width: card.width, height: 26)
        verticalGradient(ctx, sheenRect,
                         NSColor.white.withAlphaComponent(46.0 / 255.0),
                         NSColor.white.withAlphaComponent(0))
        ctx.restoreGState()

        // 外描边
        ctx.setStrokeColor(p.stroke.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(roundedPath(card.insetBy(dx: 0.5, dy: 0.5), radius))
        ctx.strokePath()

        // 上边内高光
        ctx.saveGState()
        ctx.clip(to: CGRect(x: card.minX, y: card.minY, width: card.width, height: 2.4))
        ctx.setStrokeColor(p.strokeTop.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(roundedPath(card.insetBy(dx: 1, dy: 1), radius - 1))
        ctx.strokePath()
        ctx.restoreGState()

        // 顶部 1px 纯白内沿
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(210.0 / 255.0).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: card.minX + radius * 0.55, y: card.minY + 0.6))
        ctx.addLine(to: CGPoint(x: card.maxX - radius * 0.55, y: card.minY + 0.6))
        ctx.strokePath()
    }

    private func drawRail(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        let r = CGRect(x: card.minX + 1.6, y: card.minY + 11,
                       width: L.railW, height: max(8, L.cardH - 22))
        ctx.saveGState()
        ctx.addPath(roundedPath(r, L.railW / 2))
        ctx.clip()
        verticalGradient(ctx, r, p.railFrom, p.railTo)
        ctx.restoreGState()
    }

    private func drawPills(_ ctx: CGContext, innerX: CGFloat, layout L: CardLayout, palette p: Palette) {
        let top = L.cardRect.minY + L.headY
        let h = L.pillH

        // 标签行的自适应底衬（高透明度时文字才不会飘在桌面上）
        let op = CGFloat(min(100, max(15, model.glassOpacity))) / 100.0
        let psa = min(0.55, max(0.06, 0.52 - 0.46 * op))
        let plate = (p.isDark ? NSColor.black : NSColor.white).withAlphaComponent(psa)
        let plateRect = CGRect(x: innerX - 5, y: top - 3, width: L.inner + 10, height: h + 6)
        ctx.setFillColor(plate.cgColor)
        ctx.addPath(roundedPath(plateRect, (h + 6) / 2))
        ctx.fillPath()

        let textY = top + (h - L.fsHead) / 2 - 0.5

        // 输入侧语言胶囊
        ctx.setFillColor(p.pillBg.cgColor)
        ctx.addPath(roundedPath(L.srcPillRect.offsetBy(dx: innerX - L.padX - L.railW, dy: 0), h / 2))
        ctx.fillPath()
        Typo.draw(L.srcLab, x: innerX + 9, y: textY, size: L.fsHead, color: p.textDim)

        // 对换按钮
        let swap = L.swapRect.offsetBy(dx: innerX - L.padX - L.railW, dy: 0)
        ctx.setFillColor((model.swapHover ? p.accentSoft : p.pillBg).cgColor)
        ctx.addPath(roundedPath(swap, 6))
        ctx.fillPath()
        ctx.setStrokeColor((model.swapHover ? p.accent : p.stroke).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(roundedPath(swap.insetBy(dx: 0.5, dy: 0.5), 6))
        ctx.strokePath()
        Typo.drawCentered("⇄", x: swap.minX, y: swap.minY - 1, w: swap.width, h: swap.height,
                          size: 13, color: model.swapHover ? p.accent : p.textDim, weight: .semibold)

        // 目标语言胶囊
        let tgt = L.tgtPillRect.offsetBy(dx: innerX - L.padX - L.railW, dy: 0)
        ctx.setFillColor(p.accentSoft.cgColor)
        ctx.addPath(roundedPath(tgt, h / 2))
        ctx.fillPath()
        Typo.draw(L.tgtLab, x: tgt.minX + 9, y: textY, size: L.fsHead, color: p.accent)

        var cur = tgt.maxX + 6

        // 「已吸附 · 应用名」
        if model.pinned && !model.snapLabel.isEmpty {
            let rightBound = innerX + L.inner - L.rightReserve
            let room = rightBound - cur
            if room >= 52 {
                var label = model.snapLabel
                var w = Typo.width(label, L.fsHead) + 9 + 15
                if w > room {
                    label = Typo.ellipsize(label, room - 9 - 15, L.fsHead)
                    w = room
                }
                ctx.setFillColor(p.ok.withAlphaComponent(46.0 / 255.0).cgColor)
                ctx.addPath(roundedPath(CGRect(x: cur, y: top, width: w, height: h), h / 2))
                ctx.fillPath()
                ctx.setFillColor(p.ok.cgColor)
                ctx.fillEllipse(in: CGRect(x: cur + 7, y: top + h / 2 - 2.2, width: 4.4, height: 4.4))
                Typo.draw(label, x: cur + 16, y: textY, size: L.fsHead, color: p.ok)
                cur += w + 6
            }
        }

        // 状态槽：引擎 · 耗时 · 字数 / 缓存 / 失败
        let note = model.swapHover ? I18n.shared.t("tip_swap", ConfigStore.shared.uiLang) : model.status
        let noteColor = model.swapHover ? p.accent : model.color(model.statusTone, p)
        if !note.isEmpty {
            let rightBound = L.cardRect.maxX - L.padX - L.rightReserve
            var avail = rightBound - (cur + 4)
            if avail < 20 { avail = 20 }
            var text = note
            if Typo.width(text, L.fsHead) > avail {
                text = Typo.ellipsize(text, avail, L.fsHead)
            }
            ctx.setFillColor(noteColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: cur + 1, y: top + h / 2 - 2.4, width: 4.8, height: 4.8))
            Typo.draw(text, x: cur + 10, y: textY, size: L.fsHead, color: noteColor)
        }
    }

    private func drawInputPanel(_ ctx: CGContext, layout L: CardLayout, card: CGRect, palette p: Palette) {
        let panel = L.panelRect.offsetBy(dx: card.minX, dy: card.minY)
        if model.inputFocus {
            ctx.setStrokeColor(p.accentSoft.cgColor)
            ctx.setLineWidth(3)
            ctx.addPath(roundedPath(panel.insetBy(dx: -3, dy: -3), 13))
            ctx.strokePath()
        }
        ctx.setFillColor(p.inputBg.cgColor)
        ctx.addPath(roundedPath(panel, 10))
        ctx.fillPath()
        ctx.setStrokeColor((model.inputFocus ? p.accent : p.inputBorder).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(roundedPath(panel.insetBy(dx: 0.5, dy: 0.5), 9.5))
        ctx.strokePath()

        if model.source.isEmpty {
            Typo.draw(I18n.shared.t("cue", ConfigStore.shared.uiLang),
                      x: panel.minX + 8, y: panel.minY + 7,
                      size: L.fsSrc, color: p.placeholder)
        }
    }

    private func drawMain(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        let x = card.minX + L.mainX
        var y = card.minY + L.mainY

        if model.waiting && L.mainLines.isEmpty {
            // 思考指示：三个呼吸圆点
            let base = 0.35 + 0.65 * abs(sin(Double(pulse) * .pi))
            for i in 0..<3 {
                let a = base * (i == 0 ? 1.0 : (i == 1 ? 0.75 : 0.5))
                ctx.setFillColor(p.accent.withAlphaComponent(a * 0.9).cgColor)
                ctx.fillEllipse(in: CGRect(x: x + CGFloat(i) * 9, y: y + L.mainLineH / 2 - 2.2,
                                           width: 4.4, height: 4.4))
            }
            return
        }

        for (i, line) in L.mainLines.enumerated() {
            let isLast = i == L.mainLines.count - 1
            var drawX = x
            // 流式光标画在最后一行末尾
            if model.streaming && isLast {
                let w = Typo.width(line, L.fsMain)
                if abs(sin(Double(pulse) * .pi)) > 0.35 {
                    ctx.setFillColor(p.caret.cgColor)
                    ctx.fill(CGRect(x: drawX + w + 2, y: y + 2, width: 2, height: L.mainLineH - 4))
                }
            }
            Typo.draw(line, x: drawX, y: y, size: L.fsMain, color: p.text)
            drawX += Typo.width(line, L.fsMain)
            y += L.mainLineH
        }

        if model.error && !model.warning.isEmpty {
            Typo.draw(model.warning, x: x, y: y - L.mainLineH * 0.15,
                      size: L.fsHint + 0.5, color: p.err)
        }
    }

    private func drawHints(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        var y = card.minY + L.hintY
        for line in L.hintLines {
            Typo.draw(line, x: card.minX + L.padX + L.railW, y: y, size: L.fsHint, color: p.textFaint)
            y += L.hintLineH
        }
    }

    // MARK: 头部按钮

    private func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let img = base.withSymbolConfiguration(cfg) else { return nil }
        return img.tinted(color)
    }

    private func drawButton(_ ctx: CGContext, rect: CGRect, hover: Bool, palette p: Palette,
                            symbol name: String, tint: NSColor, hoverTint: NSColor) {
        ctx.setFillColor((hover ? hoverTint.withAlphaComponent(0.22) : p.pillBg).cgColor)
        ctx.addPath(roundedPath(rect, 6))
        ctx.fillPath()
        if let img = symbol(name, size: 9, color: hover ? hoverTint : tint) {
            let s = img.size
            let r = CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2,
                           width: s.width, height: s.height)
            img.draw(in: r)
        }
    }

    private func drawCloseButton(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        let r = L.closeRect.offsetBy(dx: card.minX, dy: card.minY)
        drawButton(ctx, rect: r, hover: model.closeHover, palette: p,
                   symbol: "xmark", tint: p.textDim, hoverTint: p.err)
    }

    private func drawUnpinButton(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        let r = L.unpinRect.offsetBy(dx: card.minX, dy: card.minY)
        drawButton(ctx, rect: r, hover: model.unpinHover, palette: p,
                   symbol: "pin.slash", tint: p.textDim, hoverTint: p.accent)
    }

    private func drawNoteButton(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        let r = L.noteRect.offsetBy(dx: card.minX, dy: card.minY)
        drawButton(ctx, rect: r, hover: model.noteHover, palette: p,
                   symbol: "square.and.pencil", tint: p.textDim, hoverTint: p.accent)
    }

    /// 拖到可吸附窗口边缘：脉冲高亮条 + 居中气泡
    private func drawSnapPreview(_ ctx: CGContext, card: CGRect, layout L: CardLayout, palette p: Palette) {
        let alpha = 0.35 + 0.45 * abs(sin(Double(pulse) * .pi))
        let barH: CGFloat = 4
        let barY = model.snapPreviewEdge == 0
            ? card.minY + 2
            : card.maxY - 2 - barH
        ctx.setFillColor(p.accent.withAlphaComponent(alpha).cgColor)
        ctx.addPath(roundedPath(CGRect(x: card.minX + 8, y: barY, width: card.width - 16, height: barH), 2))
        ctx.fillPath()

        let label = model.snapLabel.isEmpty
            ? I18n.shared.t("snap_release_only", ConfigStore.shared.uiLang)
            : I18n.shared.t("snap_release", ConfigStore.shared.uiLang, [model.snapLabel])
        let w = Typo.width(label, L.fsHint) + 20
        let h: CGFloat = 20
        let rect = CGRect(x: card.midX - w / 2, y: card.midY - h / 2, width: w, height: h)
        ctx.setFillColor(p.tipBg.cgColor)
        ctx.addPath(roundedPath(rect, h / 2))
        ctx.fillPath()
        Typo.drawCentered(label, x: rect.minX, y: rect.minY, w: w, h: h,
                          size: L.fsHint, color: p.tipInk)
    }
}

extension NSImage {
    /// 给模板图标上色（NSImage 没有直接的 tint API）
    func tinted(_ color: NSColor) -> NSImage {
        let out = NSImage(size: size)
        out.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}
