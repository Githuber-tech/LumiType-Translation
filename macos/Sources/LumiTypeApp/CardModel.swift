import AppKit
import LumiTypeCore

/// 一帧卡片需要的全部状态。字段与 `CardRenderer.CardModel` 一一对应。
struct CardModel {
    var source = ""
    var result = ""
    var warning = ""
    var engineLabel = "DeepL"
    var targetLabel = "简体中文"
    var sourceLabel = "简体中文"
    var status = ""
    var statusTone: Tone = .dim
    var hints = ""

    var showSource = true
    var showPills = true
    var showHints = true
    var showLatency = true

    var waiting = false
    var streaming = false
    var error = false
    var pinned = false

    var unpinHover = false
    var swapHover = false
    var closeHover = false
    var noteHover = false

    var widthOverride: CGFloat = 0
    var inputLines = 1
    var inputFocus = true
    var snapPreview = false
    var snapPreviewEdge = 0
    var snapLabel = ""
    var resultFor = ""
    var glassOpacity = 78
    var theme: Skin = .glassDark
    var fontScale: CGFloat = 1.0

    enum Tone { case dim, ok, warn, err, accent }

    func color(_ tone: Tone, _ p: Palette) -> NSColor {
        switch tone {
        case .dim: return p.textDim
        case .ok: return p.ok
        case .warn: return p.warn
        case .err: return p.err
        case .accent: return p.accent
        }
    }
}

/// 一帧的测量结果（对应 `CardLayout`）。
/// 所有坐标都是「窗口坐标」——窗口比卡片四周各大 Margin，留给外发光。
struct CardLayout {
    var margin: CGFloat = 12
    var padX: CGFloat = 18
    var pad: CGFloat = 16
    var gap: CGFloat = 9
    var railW: CGFloat = 3
    var radius: CGFloat = 14
    var pillH: CGFloat = 21

    var fsHead: CGFloat = 9
    var fsSrc: CGFloat = 12
    var fsMain: CGFloat = 15
    var fsHint: CGFloat = 9.5

    var cardW: CGFloat = 375
    var cardH: CGFloat = 147
    var winW: CGFloat = 399
    var winH: CGFloat = 171
    var inner: CGFloat = 336

    var showPills = true
    var showSrc = true
    var showDivider = true
    var showMain = true
    var showHints = true

    var headY: CGFloat = 0
    var panelRect: CGRect = .zero
    var inputRect: CGRect = .zero

    var divY: CGFloat = 0
    var mainX: CGFloat = 0
    var mainY: CGFloat = 0
    var mainLineH: CGFloat = 20
    var mainLines: [String] = []

    var hintY: CGFloat = 0
    var hintLineH: CGFloat = 13
    var hintLines: [String] = []

    var closeRect: CGRect = .zero
    var unpinRect: CGRect = .zero
    var noteRect: CGRect = .zero
    var swapRect: CGRect = .zero
    var srcPillRect: CGRect = .zero
    var tgtPillRect: CGRect = .zero
    var srcLab = ""
    var tgtLab = ""
    var rightReserve: CGFloat = 0

    /// 卡片主体在窗口里的矩形
    var cardRect: CGRect {
        CGRect(x: margin, y: margin, width: cardW, height: cardH)
    }

    static func make(_ m: CardModel, maxWidth: CGFloat, maxHeight: CGFloat) -> CardLayout {
        var L = CardLayout()
        let fs = max(0.6, min(3.0, m.fontScale))
        L.fsHead = 9 * fs
        L.fsSrc = 12 * fs
        L.fsMain = 15 * fs
        L.fsHint = 9.5 * fs

        L.showPills = m.showPills
        L.showSrc = m.showSource
        L.showHints = m.showHints

        let mainText = m.result
        L.showMain = !mainText.isEmpty || m.waiting || m.error
        L.showDivider = L.showSrc && L.showMain

        let maxInner = maxWidth - L.padX * 2 - L.railW - L.margin * 2
        let minInner: CGFloat = 300
        let defInner = 375 - L.padX * 2 - L.railW
        var inner = m.widthOverride > 0 ? m.widthOverride - L.padX * 2 - L.railW : defInner
        inner = min(inner, maxInner)
        inner = max(inner, min(minInner, maxInner))
        L.inner = inner
        L.cardW = L.padX * 2 + L.railW + inner

        var y = L.pad
        if L.showPills {
            L.headY = y
            y += L.pillH + L.gap
        }

        let pinIn: CGFloat = 8
        let pinV: CGFloat = 6
        let inputW = inner - pinIn * 2 + 4
        let wrapW = L.showSrc ? inputW : inner

        let mainAll: [String] = L.showMain && !mainText.isEmpty
            ? Typo.wrap(mainText, width: wrapW, size: L.fsMain) : []
        let hintAll: [String] = L.showHints
            ? Typo.wrap(m.hints, width: inner, size: L.fsHint) : []

        L.mainLineH = (L.fsMain * 1.34).rounded(.up)
        L.hintLineH = (L.fsHint * 1.34).rounded(.up)

        if L.showSrc {
            let srcLineH = (L.fsSrc * 1.34).rounded(.up)
            var mainH: CGFloat = 0
            if L.showMain {
                mainH = CGFloat(max(1, min(mainAll.count, 9))) * L.mainLineH
                if m.error && !m.warning.isEmpty && !mainText.isEmpty {
                    mainH += L.mainLineH * 0.75 + 3
                }
            }
            var hintH: CGFloat = 0
            if L.showHints { hintH = L.gap + CGFloat(hintAll.count) * L.hintLineH }
            let fixedH = L.pad * 2
                + (L.showPills ? L.pillH + L.gap : 0)
                + (L.showDivider ? 1 + L.gap : 0)
                + mainH + hintH + pinV * 2 + 2
            var maxLines = Int(((maxHeight - fixedH) / srcLineH).rounded(.down))
            if maxLines < 1 { maxLines = 1 }
            let keep = max(1, min(m.inputLines, maxLines))
            let hostH = CGFloat(keep) * srcLineH + 2

            L.panelRect = CGRect(x: L.padX + L.railW, y: y, width: inner, height: hostH + pinV * 2)
            L.inputRect = CGRect(x: L.padX + L.railW + pinIn - 2, y: y + pinV,
                                 width: inputW, height: hostH)
            y += hostH + pinV * 2 + L.gap
        }

        if L.showDivider {
            L.divY = y
            y += 1 + L.gap
        }

        if L.showMain {
            L.mainY = y
            L.mainX = L.padX + L.railW + (L.showSrc ? pinIn - 2 : 0)
            if !mainAll.isEmpty {
                let keep = min(mainAll.count, 9)
                var lines = Array(mainAll.prefix(keep))
                if mainAll.count > keep, let last = lines.last {
                    lines[keep - 1] = Typo.ellipsize(last + " …", wrapW, L.fsMain)
                }
                L.mainLines = lines
            }
            y += CGFloat(max(1, L.mainLines.count)) * L.mainLineH
            if m.error && !m.warning.isEmpty && !mainText.isEmpty {
                y += L.mainLineH * 0.75 + 3
            }
        }

        if L.showHints {
            y += L.gap
            L.hintY = y
            L.hintLines = hintAll
            y += CGFloat(hintAll.count) * L.hintLineH
        }

        y += L.pad
        L.cardH = max(y, 147)
        L.winW = L.cardW + L.margin * 2
        L.winH = L.cardH + L.margin * 2

        // ---- 头部右侧按钮栈：关闭 / 解除吸附 / 记事本（V6.1.0）
        let rightX = L.cardW - L.padX
        let rowMid = L.showPills ? L.headY + L.pillH / 2 : L.pad + 9
        let btn: CGFloat = 18
        L.closeRect = CGRect(x: rightX - btn, y: rowMid - btn / 2, width: btn, height: btn)
        var bx = L.closeRect.minX - 6
        if m.pinned {
            L.unpinRect = CGRect(x: bx - btn, y: rowMid - btn / 2, width: btn, height: btn)
            bx = L.unpinRect.minX - 6
        }
        L.noteRect = CGRect(x: bx - btn, y: rowMid - btn / 2, width: btn, height: btn)
        L.rightReserve = rightX - L.noteRect.minX + 10

        // ---- 语言胶囊：输入 ⇄ 目标
        if L.showPills {
            let pad: CGFloat = 9
            let cx = L.padX + L.railW
            let swapS: CGFloat = 18
            let srcMax = inner * 0.34
            L.srcLab = Typo.ellipsize(m.sourceLabel, srcMax - pad * 2, L.fsHead)
            let srcW = Typo.width(L.srcLab, L.fsHead) + pad * 2
            L.srcPillRect = CGRect(x: cx, y: L.headY, width: srcW, height: L.pillH)
            L.swapRect = CGRect(x: L.srcPillRect.maxX + 6, y: L.headY + (L.pillH - swapS) / 2,
                                width: swapS, height: swapS)
            let tgtMax = max(60, inner - srcW - swapS - 12 - 90)
            L.tgtLab = Typo.ellipsize(m.targetLabel, tgtMax - pad * 2, L.fsHead)
            let tgtW = Typo.width(L.tgtLab, L.fsHead) + pad * 2
            L.tgtPillRect = CGRect(x: L.swapRect.maxX + 6, y: L.headY, width: tgtW, height: L.pillH)
        }
        return L
    }
}
