import AppKit
import CoreText

/// 文字排版。Windows 版用 GDI+（AntiAliasGridFit + TextContrast=6）手绘每一行；
/// Mac 侧交给 Core Text，但它只会用灰度抗锯齿 —— 正好对应原版为了避免
/// ClearType 彩色边缘而做的选择。
enum Typo {

    /// 界面字重：正文字体跟随系统（中文自动落到苹方，英文落到 SF）
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func attributes(_ size: CGFloat, _ color: NSColor,
                           _ weight: NSFont.Weight = .regular) -> [NSAttributedString.Key: Any] {
        [.font: font(size, weight), .foregroundColor: color]
    }

    static func width(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        return (s as NSString).size(withAttributes: [.font: font(size, weight)]).width
    }

    /// 按像素宽度断行。用 CTTypesetter 而不是 `boundingRect`：
    /// 后者只给高度，拿不到每一行的内容，而卡片需要逐行绘制（末行省略号、光标定位）。
    static func wrap(_ s: String, width: CGFloat, size: CGFloat,
                     _ weight: NSFont.Weight = .regular) -> [String] {
        guard !s.isEmpty, width > 1 else { return [] }
        let attr = NSAttributedString(string: s, attributes: [.font: font(size, weight)])
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        let ns = s as NSString
        var lines: [String] = []
        var start = 0
        while start < ns.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 { break }
            var line = ns.substring(with: NSRange(location: start, length: count))
            while line.hasSuffix("\n") || line.hasSuffix("\r") {
                line.removeLast()
            }
            lines.append(line)
            start += count
        }
        return lines
    }

    /// 单行省略（对应 `CardRenderer.Ellipsize`：二分找能放下的最长前缀）
    static func ellipsize(_ s: String, _ maxWidth: CGFloat, _ size: CGFloat,
                          _ weight: NSFont.Weight = .regular) -> String {
        if s.isEmpty { return s }
        if width(s, size, weight) <= maxWidth { return s }
        var lo = 0, hi = s.count - 1, best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cand = String(s.prefix(mid)).trimmingCharacters(in: .whitespaces) + "…"
            if width(cand, size, weight) <= maxWidth {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best <= 0 ? "…" : String(s.prefix(best)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// 在 flipped 视图坐标系里画一行（y 为文字顶部）
    static func draw(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat,
                     color: NSColor, weight: NSFont.Weight = .regular) {
        guard !s.isEmpty else { return }
        NSAttributedString(string: s, attributes: attributes(size, color, weight)).draw(at: NSPoint(x: x, y: y))
    }

    /// 状态行/胶囊里的垂直居中文案
    static func drawCentered(_ s: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                             size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
        guard !s.isEmpty else { return }
        let tw = width(s, size, weight)
        let lineH = font(size, weight).ascender - font(size, weight).descender
        draw(s, x: x + max(0, (w - tw) / 2), y: y + (h - lineH) / 2, size: size, color: color, weight: weight)
    }
}
