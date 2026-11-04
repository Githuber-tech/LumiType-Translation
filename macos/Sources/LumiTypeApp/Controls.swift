import AppKit
import LumiTypeCore

/// 自上而下排布的表单容器（flipped，才能在 y 轴上「往下加」）
final class FlippedView: NSView {
    override var isFlipped: Bool { true }

    var cursorY: CGFloat = 0
    let contentWidth: CGFloat

    init(width: CGFloat) {
        contentWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func advance(_ dy: CGFloat) {
        cursorY += dy
        frame.size.height = max(cursorY, 10)
    }

    /// 加一行控件，返回控件本身方便后续改状态
    @discardableResult
    func place<T: NSView>(_ view: T, x: CGFloat = 0, y: CGFloat? = nil, height: CGFloat) -> T {
        view.frame = NSRect(x: x, y: y ?? cursorY, width: view.frame.width, height: height)
        addSubview(view)
        if y == nil { advance(height) }
        return view
    }
}

enum Controls {

    static func label(_ text: String, size: CGFloat = 12,
                      color: NSColor = .labelColor, bold: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold)
                          : NSFont.systemFont(ofSize: size)
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.preferredMaxLayoutWidth = 560
        return field
    }

    /// 说明文字：固定宽度、高度按内容算
    static func note(_ text: String, width: CGFloat) -> NSTextField {
        let field = label(text, size: 11, color: .secondaryLabelColor)
        field.preferredMaxLayoutWidth = width
        let height = field.sizeThatFits(NSSize(width: width, height: 400)).height
        field.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return field
    }

    static func sectionTitle(_ text: String) -> NSTextField {
        label(text, size: 12, color: .labelColor, bold: true)
    }

    static func checkbox(_ title: String, on: Bool, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        button.state = on ? .on : .off
        button.font = NSFont.systemFont(ofSize: 12)
        button.sizeToFit()
        return button
    }

    static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 12)
        button.sizeToFit()
        return button
    }

    static func textField(_ value: String, width: CGFloat, secure: Bool = false) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        field.stringValue = value
        field.font = NSFont.systemFont(ofSize: 12)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        if secure { field.cell?.usesSingleLineMode = true }
        return field
    }

    static func popup(_ items: [String], selected: Int, target: AnyObject, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 24), pullsDown: false)
        popup.addItems(withTitles: items)
        if selected >= 0 && selected < items.count { popup.selectItem(at: selected) }
        popup.target = target
        popup.action = action
        popup.font = NSFont.systemFont(ofSize: 12)
        return popup
    }

    static func radio(_ title: String, on: Bool, tag: Int, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: target, action: action)
        button.state = on ? .on : .off
        button.tag = tag
        button.font = NSFont.systemFont(ofSize: 12)
        button.sizeToFit()
        return button
    }

    static func scroll(_ document: NSView, frame: NSRect) -> NSScrollView {
        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        document.frame = NSRect(x: 0, y: 0, width: frame.width, height: max(document.frame.height, frame.height))
        scroll.documentView = document
        return scroll
    }
}

/// 快捷键录入框：点一下开始录，按 Esc 取消。
/// 三条错误分别对应 `hk_err_mod` / `hk_err_key` / `hk_err_busy`。
final class HotkeyRecorderView: NSView {

    var canonical: String = "" {
        didSet { needsDisplay = true }
    }
    var onCommit: ((KeyCombo) -> Void)?
    var onError: ((String) -> Void)?

    private var recording = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == 53 {          // Esc 取消
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        let flags = event.modifierFlags
        let hasModifier = flags.contains(.control) || flags.contains(.option)
            || flags.contains(.shift) || flags.contains(.command)
        guard hasModifier else {
            onError?("hk_err_mod")
            return
        }
        guard let combo = KeyMap.from(event: event) else {
            onError?("hk_err_key")
            return
        }
        canonical = combo.canonical
        recording = false
        window?.makeFirstResponder(nil)
        onCommit?(combo)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let store = ConfigStore.shared
        let text: String
        if recording {
            text = store.t("hk_capture")
        } else if let combo = KeyMap.parse(canonical) {
            text = combo.display + "   (" + canonical + ")"
        } else {
            text = canonical
        }
        Typo.drawCentered(text, x: 8, y: 0, w: bounds.width - 16, h: bounds.height,
                          size: 12, color: recording ? .controlAccentColor : .labelColor)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }
}
