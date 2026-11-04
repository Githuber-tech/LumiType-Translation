import AppKit

/// 图标绘制：青→紫渐变的圆角方块 + 白色「译」。
/// 对应原版 `IconArt`（任务栏与托盘用的是同一套几何）。
enum IconArt {

    static func image(size: CGFloat, glyph: String = "译") -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        defer { img.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.235
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06),
                                xRadius: radius, yRadius: radius)
        path.addClip()

        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.18, green: 0.83, blue: 0.94, alpha: 1),
            NSColor(srgbRed: 0.65, green: 0.47, blue: 0.98, alpha: 1)
        ])
        gradient?.draw(in: path, angle: -70)

        // 顶部高光
        NSColor.white.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + size * 0.1, y: rect.midY,
                                         width: size * 0.8, height: size * 0.38),
                     xRadius: radius * 0.7, yRadius: radius * 0.7).fill()

        let font = NSFont.systemFont(ofSize: size * 0.52, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: glyph, attributes: attrs)
        let ts = text.size()
        text.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2))
        return img
    }

    /// 托盘图标：18×18 的彩色渐变（Mac 菜单栏也接受彩色图标）
    static func statusImage() -> NSImage {
        let img = image(size: 18)
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    /// 导出 PNG（构建脚本用它生成 .icns）
    static func writePNG(size: CGFloat, to url: URL) -> Bool {
        let img = image(size: size)
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
