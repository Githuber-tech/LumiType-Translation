import AppKit
import LumiTypeCore

/// 设计令牌 —— 逐条对应 `src/CardRenderer.cs` 的 `Theme`（24 个颜色 × 3 套皮肤）。
/// 颜色的 ARGB 值与 Windows 版完全一致，保证「换平台不换脸」。
struct Palette {

    var bgTop: NSColor
    var bgBottom: NSColor
    var stroke: NSColor
    var strokeTop: NSColor
    var railFrom: NSColor
    var railTo: NSColor
    var text: NSColor
    var textDim: NSColor
    var textFaint: NSColor
    var accent: NSColor
    var accentSoft: NSColor
    var ok: NSColor
    var warn: NSColor
    var err: NSColor
    var pillBg: NSColor
    var divider: NSColor
    var caret: NSColor
    var sel: NSColor
    var shadow: NSColor
    var inputBg: NSColor
    var inputBorder: NSColor
    var placeholder: NSColor
    var tipBg: NSColor
    var tipInk: NSColor

    /// 皮肤是否为深色（决定标签底衬用黑还是白）
    var isDark: Bool {
        let c = bgTop.usingColorSpace(.sRGB) ?? bgTop
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent < 0.5
    }

    static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: CGFloat(a) / 255.0)
    }

    static func mix(_ x: NSColor, _ y: NSColor, _ t: CGFloat) -> NSColor {
        let a = x.usingColorSpace(.sRGB) ?? x
        let b = y.usingColorSpace(.sRGB) ?? y
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: 1.0)
    }

    static func make(_ skin: Skin) -> Palette {
        switch skin {
        case .glassDark: return dark()
        case .paperLight: return paper()
        case .accentGlass: return accent(systemAccent())
        }
    }

    /// 系统强调色（对应 Windows 的 DWM 颜色化色）
    static func systemAccent() -> NSColor {
        let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.37, green: 0.91, blue: 0.96, alpha: 1)
        return c
    }

    static func dark() -> Palette {
        Palette(
            bgTop: rgba(30, 36, 49, 244),
            bgBottom: rgba(16, 20, 29, 242),
            stroke: rgba(255, 255, 255, 48),
            strokeTop: rgba(255, 255, 255, 85),
            railFrom: rgba(47, 216, 240),
            railTo: rgba(167, 139, 250),
            text: rgba(243, 246, 251),
            textDim: rgba(169, 179, 196),
            textFaint: rgba(110, 120, 137),
            accent: rgba(95, 231, 245),
            accentSoft: rgba(47, 216, 240, 51),
            ok: rgba(74, 222, 128),
            warn: rgba(251, 191, 36),
            err: rgba(251, 113, 133),
            pillBg: rgba(255, 255, 255, 28),
            divider: rgba(255, 255, 255, 28),
            caret: rgba(95, 231, 245),
            sel: rgba(95, 231, 245, 96),
            shadow: rgba(0, 0, 0, 34),
            inputBg: rgba(36, 42, 56),
            inputBorder: rgba(70, 80, 100),
            placeholder: rgba(104, 112, 130),
            tipBg: rgba(12, 16, 24, 242),
            tipInk: rgba(243, 246, 251)
        )
    }

    static func paper() -> Palette {
        Palette(
            bgTop: rgba(255, 255, 255, 255),
            bgBottom: rgba(242, 245, 250, 253),
            stroke: rgba(0, 0, 0, 34),
            strokeTop: rgba(0, 0, 0, 51),
            railFrom: rgba(99, 102, 241),
            railTo: rgba(14, 165, 233),
            text: rgba(21, 24, 31),
            textDim: rgba(90, 100, 114),
            textFaint: rgba(140, 149, 163),
            accent: rgba(79, 70, 229),
            accentSoft: rgba(99, 102, 241, 34),
            ok: rgba(22, 163, 74),
            warn: rgba(217, 119, 6),
            err: rgba(220, 38, 38),
            pillBg: rgba(0, 0, 0, 20),
            divider: rgba(0, 0, 0, 20),
            caret: rgba(79, 70, 229),
            sel: rgba(79, 70, 229, 96),
            shadow: rgba(15, 23, 42, 42),
            inputBg: rgba(252, 253, 255),
            inputBorder: rgba(226, 233, 242),
            placeholder: rgba(150, 158, 172),
            tipBg: rgba(252, 252, 254, 246),
            tipInk: rgba(21, 24, 31)
        )
    }

    /// 跟随系统强调色：粉系统 = 粉面板，紫系统 = 紫面板（对应 `ApplyAccent`）
    static func accent(_ a: NSColor) -> Palette {
        let c = a.usingColorSpace(.sRGB) ?? a
        let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        let white = NSColor.white
        let tintTop = mix(c, white, lum > 0.62 ? 0.55 : 0.72)
        let tintBot = mix(c, white, lum > 0.62 ? 0.38 : 0.58)
        let darkInk = lum > 0.30
        let black = NSColor.black
        let pw: CGFloat = darkInk ? 0 : 1
        let ib = mix(c, white, 0.84)
        let ibd = mix(c, white, 0.45)
        let ink = darkInk ? rgba(24, 26, 33) : rgba(250, 250, 252)
        let inkDim = darkInk ? rgba(66, 72, 84) : rgba(224, 226, 232)
        let inkFaint = darkInk ? rgba(108, 116, 128) : rgba(188, 192, 200)
        return Palette(
            bgTop: tintTop.withAlphaComponent(244.0 / 255.0),
            bgBottom: tintBot.withAlphaComponent(242.0 / 255.0),
            stroke: rgba(255, 255, 255, 60),
            strokeTop: rgba(255, 255, 255, 95),
            railFrom: c,
            railTo: mix(c, white, 0.35),
            text: ink,
            textDim: inkDim,
            textFaint: inkFaint,
            accent: darkInk ? mix(c, black, 0.28) : mix(c, white, 0.30),
            accentSoft: c.withAlphaComponent(51.0 / 255.0),
            ok: darkInk ? rgba(22, 163, 74) : rgba(74, 222, 128),
            warn: darkInk ? rgba(217, 119, 6) : rgba(251, 191, 36),
            err: darkInk ? rgba(220, 38, 38) : rgba(251, 113, 133),
            pillBg: NSColor(srgbRed: pw, green: pw, blue: pw, alpha: 30.0 / 255.0),
            divider: NSColor(srgbRed: pw, green: pw, blue: pw, alpha: 30.0 / 255.0),
            caret: darkInk ? mix(c, black, 0.28) : mix(c, white, 0.30),
            sel: c.withAlphaComponent(96.0 / 255.0),
            shadow: NSColor(srgbRed: c.redComponent / 3, green: c.greenComponent / 3,
                            blue: c.blueComponent / 3, alpha: 40.0 / 255.0),
            inputBg: ib,
            inputBorder: ibd,
            placeholder: inkFaint,
            tipBg: darkInk ? rgba(255, 255, 255, 246) : rgba(16, 18, 26, 242),
            tipInk: ink
        )
    }
}

enum Skin: String, CaseIterable {
    case paperLight = "paper-light"
    case glassDark = "glass-dark"
    case accentGlass = "accent-glass"

    var titleKey: String {
        switch self {
        case .paperLight: return "skin_light"
        case .glassDark: return "skin_dark"
        case .accentGlass: return "skin_accent"
        }
    }

    static func from(_ raw: String) -> Skin {
        Skin(rawValue: raw) ?? .glassDark
    }
}
