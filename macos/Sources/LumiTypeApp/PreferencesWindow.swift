import AppKit
import LumiTypeCore

/// 首选项窗口：四个分页（常规 / 更新日志 / 使用技巧 / 用户反馈）。
/// 布局、分组、控件顺序照 `PrefsForm.cs`，文案全部来自 I18n 表（与 exe 逐字一致）。
final class PreferencesWindowController: NSWindowController {

    private let tabs = NSTabView()
    private var general: GeneralPage?
    private var changelog: ChangelogPage?
    private var tips: TipsPage?
    private var feedback: FeedbackPage?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 664, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = ConfigStore.shared.t("prefs_title")
        window.minSize = NSSize(width: 460, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        build()
    }

    private func build() {
        guard let window else { return }
        tabs.frame = window.contentView?.bounds ?? .zero
        tabs.autoresizingMask = [.width, .height]
        tabs.tabViewType = .topTabsBezelBorder
        window.contentView?.addSubview(tabs)
        rebuildTabs()
    }

    /// 自检用：切到指定分页（0 常规 / 1 更新日志 / 2 使用技巧 / 3 用户反馈）
    func selectTab(_ index: Int) {
        guard index >= 0, index < tabs.numberOfTabViewItems else { return }
        tabs.selectTabViewItem(at: index)
    }

    /// 自检用：首选项窗口截图（纯 AppKit 控件，不含毛玻璃 -> 安全）
    func captureSnapshot(to path: String) {
        guard let content = window?.contentView else { return }
        Snapshot.write(content, to: path)
    }

    func rebuildTabs() {
        let selected = tabs.selectedTabViewItem.map { tabs.indexOfTabViewItem($0) } ?? 0
        tabs.tabViewItems.forEach { tabs.removeTabViewItem($0) }

        let store = ConfigStore.shared
        general = GeneralPage()
        changelog = ChangelogPage()
        tips = TipsPage()
        feedback = FeedbackPage()

        let items: [(String, NSView)] = [
            (store.t("tab_general"), general!.view),
            (store.t("tab_log"), changelog!.view),
            (store.t("tab_tips"), tips!.view),
            (store.t("tab_feedback"), feedback!.view)
        ]
        for (title, view) in items {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        if selected >= 0, selected < tabs.numberOfTabViewItems {
            tabs.selectTabViewItem(at: selected)
        }
        window?.title = store.t("prefs_title")
    }
}

// MARK: - 常规页

final class GeneralPage: NSObject {

    let view: NSView
    private let container = FlippedView(width: 612)
    private let scroll: NSScrollView

    private var statusLabel: NSTextField!
    private var autoCheck: NSButton!
    private var adminCheck: NSButton!
    private var toggleRecorder: HotkeyRecorderView!
    private var clipRecorder: HotkeyRecorderView!
    private var glassSlider: NSSlider!
    private var glassValue: NSTextField!
    private var skinRadios: [NSButton] = []
    private var deeplField: NSTextField!
    private var googleField: NSTextField!
    private var llmField: NSTextField!
    private var endpointField: NSTextField!
    private var modelField: NSTextField!
    private var deeplStatus: NSTextField!
    private var googleStatus: NSTextField!
    private var llmStatus: NSTextField!
    private var langPopup: NSPopUpButton!

    private var store: ConfigStore { .shared }
    private var cfg: Config { store.config }
    private var y: CGFloat = 0
    private let width: CGFloat = 612

    override init() {
        scroll = Controls.scroll(container, frame: NSRect(x: 0, y: 0, width: 640, height: 700))
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 700))
        super.init()
        scroll.autoresizingMask = [.width, .height]
        view.addSubview(scroll)
        build()
    }

    // MARK: 布局工具

    private func add(_ v: NSView, height: CGFloat, gap: CGFloat = 8, x: CGFloat = 0) {
        v.frame = NSRect(x: x, y: y, width: v.frame.width, height: height)
        container.addSubview(v)
        y += height + gap
    }

    private func addText(_ text: String, size: CGFloat = 12, bold: Bool = false,
                         color: NSColor = .labelColor, gap: CGFloat = 8) {
        let field = Controls.label(text, size: size, color: color, bold: bold)
        field.frame = NSRect(x: 0, y: 0, width: width, height: 16)
        let h = field.sizeThatFits(NSSize(width: width, height: 400)).height
        add(field, height: max(16, h), gap: gap)
    }

    private func addNote(_ text: String, gap: CGFloat = 12) {
        let field = Controls.note(text, width: width)
        add(field, height: field.frame.height, gap: gap)
    }

    private func addSection(_ title: String) {
        y += 4
        addText(title, size: 12, bold: true, gap: 8)
    }

    // MARK: 构建

    private func build() {
        let c = cfg
        statusLabel = Controls.label(store.t("state", [Product.versionText, permissionText,
                                                       c.autoStart ? store.t("state_on") : store.t("state_off")]),
                                     size: 11, color: .secondaryLabelColor)
        add(statusLabel, height: 16, gap: 10)

        autoCheck = Controls.checkbox(store.t("autostart"), on: c.autoStart, target: self, action: #selector(toggleAutoStart))
        add(autoCheck, height: 20, gap: 6)

        adminCheck = Controls.checkbox(store.t("admin"), on: false, target: self, action: #selector(noop))
        adminCheck.isEnabled = false
        add(adminCheck, height: 20, gap: 4)
        addNote(store.t("admin_note_mac"), gap: 10)

        // 快捷键
        addSection(store.t("hotkey_group"))
        addHotkeyRow(title: store.t("hk_toggle"), recording: c.hotkeyToggle) { [weak self] combo in
            self?.commitHotkey(toggle: combo.canonical, clipboard: nil)
        }
        addHotkeyRow(title: store.t("hk_clipboard"), recording: c.hotkeyClipboard) { [weak self] combo in
            self?.commitHotkey(toggle: nil, clipboard: combo.canonical)
        }
        addNote(store.t("hk_h1") + "　·　" + store.t("hk_h2"), gap: 8)
        let reset = Controls.button(store.t("hk_reset"), target: self, action: #selector(resetHotkeys))
        reset.bezelStyle = .rounded
        reset.frame.size = NSSize(width: max(150, reset.frame.width + 24), height: 24)
        add(reset, height: 24, gap: 12)

        // 皮肤与浓度
        addSection(store.t("glass_group"))
        glassSlider = NSSlider(value: Double(c.glassOpacity), minValue: 15, maxValue: 100,
                               target: self, action: #selector(glassChanged))
        glassSlider.frame = NSRect(x: 0, y: 0, width: 460, height: 24)
        glassSlider.isContinuous = true
        glassValue = Controls.label("\(c.glassOpacity)%", size: 12)
        glassValue.frame = NSRect(x: 0, y: 0, width: 60, height: 20)
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        glassSlider.frame.origin = NSPoint(x: 0, y: 0)
        glassValue.frame.origin = NSPoint(x: 474, y: 2)
        row.addSubview(glassSlider)
        row.addSubview(glassValue)
        add(row, height: 24, gap: 4)
        addNote(store.t("glass_help"), gap: 10)

        addText(store.t("skin_group"), size: 12, bold: true, gap: 6)
        let skins: [(Skin, String)] = [(.paperLight, "skin_light"), (.glassDark, "skin_dark"), (.accentGlass, "skin_accent")]
        // 原版是一行三个单选（起始 x=18，每个 192 宽、步进 196），这里照排
        let skinRow = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        for (index, entry) in skins.enumerated() {
            let radio = Controls.radio(store.t(entry.1), on: Skin.from(c.theme) == entry.0,
                                       tag: index, target: self, action: #selector(skinChanged))
            radio.sizeToFit()
            radio.frame = NSRect(x: CGFloat(index) * 196 + 18, y: 0, width: 192, height: 22)
            skinRow.addSubview(radio)
            skinRadios.append(radio)
        }
        add(skinRow, height: 22, gap: 2)
        addNote(store.t("skin_help"), gap: 12)

        // 引擎
        addSection(store.t("engine_group"))
        deeplField = Controls.textField(c.deeplKey.isEmpty ? c.apiKey : c.deeplKey, width: 300)
        deeplStatus = engineStatus(for: .deepl)
        addEngineRow(title: "DeepL", field: deeplField, status: deeplStatus, action: #selector(applyDeepl))

        googleField = Controls.textField(c.googleKey, width: 300)
        googleStatus = engineStatus(for: .google)
        addEngineRow(title: store.t("eng_google"), field: googleField, status: googleStatus, action: #selector(applyGoogle))

        llmField = Controls.textField(c.llmKey, width: 300)
        llmStatus = engineStatus(for: .llm)
        addEngineRow(title: store.t("eng_llm"), field: llmField, status: llmStatus, action: #selector(applyLlm))

        addText("LLM Endpoint", size: 11, color: .secondaryLabelColor, gap: 4)
        endpointField = Controls.textField(c.llmEndpoint, width: 420)
        add(endpointField, height: 22, gap: 6)
        addText("LLM Model", size: 11, color: .secondaryLabelColor, gap: 4)
        modelField = Controls.textField(c.llmModel, width: 260)
        add(modelField, height: 22, gap: 6)
        addNote(store.t("api_help"), gap: 12)

        // 界面语言
        addSection(store.t("uilang_group"))
        langPopup = Controls.popup(["简体中文", "English"], selected: c.uiLang == "en" ? 1 : 0,
                                   target: self, action: #selector(langChanged))
        add(langPopup, height: 26, gap: 4)
        addNote(store.t("uilang_help"), gap: 12)

        // 配置目录
        addSection(store.t("cfg_group"))
        let openBtn = Controls.button(store.t("cfg_open"), target: self, action: #selector(openConfig))
        let reloadBtn = Controls.button(store.t("cfg_reload"), target: self, action: #selector(reloadConfig))
        let btnRow = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        openBtn.frame.origin = NSPoint(x: 0, y: 0)
        reloadBtn.frame.origin = NSPoint(x: openBtn.frame.width + 10, y: 0)
        btnRow.addSubview(openBtn)
        btnRow.addSubview(reloadBtn)
        add(btnRow, height: 26, gap: 12)

        y += 12
        container.frame.size.height = y
    }

    private func addHotkeyRow(title: String, recording: String, onCommit: @escaping (KeyCombo) -> Void) {
        let label = Controls.label(title, size: 12)
        label.frame = NSRect(x: 0, y: 6, width: 190, height: 18)
        let recorder = HotkeyRecorderView(frame: NSRect(x: 196, y: 0, width: 250, height: 28))
        recorder.canonical = recording
        recorder.onCommit = onCommit
        recorder.onError = { [weak self] key in
            self?.showError(self?.store.t(key) ?? key)
        }
        if title == store.t("hk_toggle") { toggleRecorder = recorder } else { clipRecorder = recorder }
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        row.addSubview(label)
        row.addSubview(recorder)
        add(row, height: 28, gap: 6)
    }

    private func engineStatus(for provider: Provider) -> NSTextField {
        let configured = cfg.isConfigured(provider)
        let active = cfg.provider == provider.rawValue
        var text = configured ? store.t("api_yes") : store.t("api_no")
        if active { text += " · " + store.t("api_active") }
        let field = Controls.label(text, size: 11,
                                   color: configured ? .systemGreen : .secondaryLabelColor)
        field.frame.size.width = 120
        return field
    }

    private func addEngineRow(title: String, field: NSTextField, status: NSTextField, action: Selector) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        let label = Controls.label(title, size: 12)
        label.frame = NSRect(x: 0, y: 5, width: 120, height: 18)
        field.frame = NSRect(x: 124, y: 2, width: 296, height: 22)
        let apply = Controls.button(store.t("api_apply"), target: self, action: action)
        apply.frame.origin = NSPoint(x: 428, y: 0)
        status.frame = NSRect(x: 492, y: 5, width: width - 492, height: 16)
        row.addSubview(label)
        row.addSubview(field)
        row.addSubview(apply)
        row.addSubview(status)
        add(row, height: 28, gap: 6)
    }

    // MARK: 动作

    @objc private func noop() {}

    @objc private func toggleAutoStart() {
        let next = autoCheck.state == .on
        let ok = AutoStart.set(next)
        if !ok {
            autoCheck.state = next ? .off : .on
            showError(store.t("upd_installfail", ["LaunchAgent"]))
            return
        }
        store.update { $0.autoStart = next }
        refreshStatus()
    }

    /// macOS 没有「管理员权限」这个概念，同一栏位改报「辅助功能」授权状态：
    /// 它才是决定「能不能把译文自动插入别的应用」的唯一权限。
    private var permissionText: String {
        store.t(PasteService.hasAccessibility ? "perm_ax_on" : "perm_ax_off")
    }

    private func refreshStatus() {
        statusLabel.stringValue = store.t("state", [Product.versionText, permissionText,
                                                    cfg.autoStart ? store.t("state_on") : store.t("state_off")])
    }

    private func commitHotkey(toggle: String?, clipboard: String?) {
        let newToggle = toggle ?? cfg.hotkeyToggle
        let newClip = clipboard ?? cfg.hotkeyClipboard
        let result = HotkeyManager.shared.apply(toggle: newToggle, clipboard: newClip)
        guard result.toggle && result.clipboard else {
            showError(store.t("hk_err_busy"))
            toggleRecorder.canonical = cfg.hotkeyToggle
            clipRecorder.canonical = cfg.hotkeyClipboard
            HotkeyManager.shared.apply(toggle: cfg.hotkeyToggle, clipboard: cfg.hotkeyClipboard)
            return
        }
        store.update {
            $0.hotkeyToggle = newToggle
            $0.hotkeyClipboard = newClip
        }
    }

    @objc private func resetHotkeys() {
        HotkeyManager.shared.apply(toggle: "Alt+Y", clipboard: "Ctrl+Alt+Y")
        store.update {
            $0.hotkeyToggle = "Alt+Y"
            $0.hotkeyClipboard = "Ctrl+Alt+Y"
        }
        toggleRecorder.canonical = "Alt+Y"
        clipRecorder.canonical = "Ctrl+Alt+Y"
    }

    @objc private func glassChanged() {
        let value = Int(glassSlider.doubleValue.rounded())
        glassValue.stringValue = "\(value)%"
        store.update { $0.glassOpacity = value }
    }

    @objc private func skinChanged(_ sender: NSButton) {
        let skins: [Skin] = [.paperLight, .glassDark, .accentGlass]
        let skin = skins[max(0, min(skins.count - 1, sender.tag))]
        store.update { $0.theme = skin.rawValue }
    }

    @objc private func applyDeepl() {
        let key = deeplField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { showError(store.t("api_nokey")); return }
        store.update {
            $0.deeplKey = key
            $0.provider = Provider.deepl.rawValue
        }
        deeplStatus.stringValue = store.t("api_yes") + " · " + store.t("api_active")
        deeplStatus.textColor = .systemGreen
        googleStatus.stringValue = cfg.isConfigured(.google) ? store.t("api_yes") : store.t("api_no")
        llmStatus.stringValue = cfg.isConfigured(.llm) ? store.t("api_yes") : store.t("api_no")
    }

    @objc private func applyGoogle() {
        let key = googleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { showError(store.t("api_nokey")); return }
        store.update {
            $0.googleKey = key
            $0.provider = Provider.google.rawValue
        }
        googleStatus.stringValue = store.t("api_yes") + " · " + store.t("api_active")
        googleStatus.textColor = .systemGreen
    }

    @objc private func applyLlm() {
        let key = llmField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { showError(store.t("api_nokey")); return }
        let endpoint = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update {
            $0.llmKey = key
            $0.llmEndpoint = endpoint.isEmpty ? $0.llmEndpoint : endpoint
            $0.llmModel = model.isEmpty ? $0.llmModel : model
            $0.provider = Provider.llm.rawValue
        }
        llmStatus.stringValue = store.t("api_yes") + " · " + store.t("api_active")
        llmStatus.textColor = .systemGreen
    }

    @objc private func langChanged() {
        let lang = langPopup.indexOfSelectedItem == 1 ? "en" : "zh"
        store.update { $0.uiLang = lang }
        (window?.windowController as? PreferencesWindowController)?.rebuildTabs()
    }

    @objc private func openConfig() {
        AppPaths.reveal(AppPaths.support)
    }

    @objc private func reloadConfig() {
        store.reload()
        (window?.windowController as? PreferencesWindowController)?.rebuildTabs()
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    private var window: NSWindow? { view.window }
}

// MARK: - 更新日志页

final class ChangelogPage: NSObject {
    let view: NSView

    override init() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 700))
        super.init()
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 700))
        text.isEditable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.textStorage?.setAttributedString(render())
        let scroll = NSScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = text
        text.autoresizingMask = [.width]
        view.addSubview(scroll)
    }

    private func render() -> NSAttributedString {
        let store = ConfigStore.shared
        let out = NSMutableAttributedString()
        for entry in Changelog.all {
            let version = "V\(entry.version)"
            let kind = Changelog.kindLabel(entry.kind, store.uiLang)
            let head = kind.isEmpty ? version : "\(version) · \(kind)"
            out.append(NSAttributedString(string: head + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]))
            out.append(NSAttributedString(string: Changelog.title(entry, store.uiLang) + "\n\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        return out
    }
}

// MARK: - 使用技巧页

final class TipsPage: NSObject {
    let view: NSView
    private let container = FlippedView(width: 612)

    override init() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 700))
        super.init()
        let scroll = Controls.scroll(container, frame: view.bounds)
        scroll.autoresizingMask = [.width, .height]
        view.addSubview(scroll)
        build()
    }

    private func build() {
        let store = ConfigStore.shared
        var y: CGFloat = 8
        func add(_ v: NSView, _ h: CGFloat, gap: CGFloat = 8) {
            v.frame = NSRect(x: 0, y: y, width: v.frame.width, height: h)
            container.addSubview(v)
            y += h + gap
        }

        let tips: [(String, String, Bool)] = [
            ("tip1_t", store.uiLang == "en"
                ? "Badge row on top, rounded input box, live translation, hint row. The two 44 px bands outside the top/bottom edges are snap zones."
                : "顶部是徽章行与关闭按钮，中间是圆角输入框，下面是实时译文与快捷键提示。卡片上下外框各 44px 是吸附热区。", true),
            ("tip2_t", store.uiLang == "en"
                ? "Drag the card near the top or bottom edge of a chat window; release to snap. The card follows resizes and closes when the window closes."
                : "把卡片拖到聊天窗口的上/下外框附近，出现高亮后松手即吸附；之后宽度跟随窗口，窗口关闭时浮层自动关闭。", true),
            ("tip3_t", store.uiLang == "en"
                ? "Enter inserts the translation, ⌃Enter the original, ⇧Enter adds a line, Tab cycles engines, Esc closes the overlay."
                : "Enter 输出译文，Ctrl+Enter 输出原文，Shift+Enter 换行，Tab 在已配置的引擎间循环，Esc 关闭浮层。", false),
            ("tip4_t", store.uiLang == "en"
                ? "Every summon creates an independent overlay: each keeps its own text and translation. Esc closes only the focused one."
                : "每次唤出都是独立实例，各自维护输入与译文；Esc 只关闭当前获得焦点的那个。", false),
            ("tip5_t", store.uiLang == "en"
                ? "DeepL: sign up for API Free, copy the key from the account page (it ends with :fx), paste it above and press Apply."
                : "DeepL：注册 API Free → 账户页复制 Key（免费版以 :fx 结尾）→ 粘贴到上方并点「应用」。", false),
            ("tip6_t", store.uiLang == "en"
                ? "Google: open Cloud Console, create a project, enable Cloud Translation API, then create an API key (starts with AIza)."
                : "Google：打开 Cloud Console → 新建项目并启用 Cloud Translation API → 凭据里创建 API Key（以 AIza 开头）。", false),
            ("tip7_t", store.uiLang == "en"
                ? "LLM: DeepSeek platform → top up → API keys → create sk-… Then set the endpoint and model above."
                : "LLM：DeepSeek 开放平台 → 充值 → API keys → 创建 sk-…，再在上方填 Endpoint 与 Model。", false)
        ]

        for (index, tip) in tips.enumerated() {
            let title = Controls.label(store.t(tip.0), size: 12, bold: true)
            let titleHeight = title.sizeThatFits(NSSize(width: 600, height: 60)).height
            add(title, max(18, titleHeight), gap: 4)

            if tip.2 {
                let diagram = TipDiagramView(kind: index == 0 ? .cardAnatomy : .snap, lang: store.uiLang)
                add(diagram, 168, gap: 6)
            }
            let body = Controls.note(tip.1, width: 600)
            add(body, body.frame.height, gap: 14)
        }
        y += 10
        container.frame.size.height = y
    }
}

/// 使用技巧里的矢量图示（原版是运行时 GDI+ 绘制，这里用 Core Graphics 重画）
final class TipDiagramView: NSView {

    enum Kind { case cardAnatomy, snap }
    let kind: Kind
    let lang: String

    init(kind: Kind, lang: String) {
        self.kind = kind
        self.lang = lang
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 168))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.dark()
        let card = CGRect(x: 40, y: 10, width: 300, height: 120)
        let path = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        p.bgTop.setFill()
        path.fill()
        p.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        // 语言胶囊
        let pill = NSBezierPath(roundedRect: CGRect(x: card.minX + 14, y: card.minY + 12, width: 60, height: 16),
                                xRadius: 8, yRadius: 8)
        p.pillBg.setFill(); pill.fill()
        Typo.draw("简体中文", x: card.minX + 20, y: card.minY + 13, size: 8, color: p.textDim)

        let pill2 = NSBezierPath(roundedRect: CGRect(x: card.minX + 86, y: card.minY + 12, width: 42, height: 16),
                                 xRadius: 8, yRadius: 8)
        p.accentSoft.setFill(); pill2.fill()
        Typo.draw("English", x: card.minX + 92, y: card.minY + 13, size: 8, color: p.accent)

        // 输入框
        let input = NSBezierPath(roundedRect: CGRect(x: card.minX + 14, y: card.minY + 36,
                                                     width: card.width - 28, height: 30),
                                 xRadius: 8, yRadius: 8)
        p.inputBg.setFill(); input.fill()
        p.inputBorder.setStroke(); input.lineWidth = 1; input.stroke()
        Typo.draw(lang == "en" ? "type here…" : "在这里输入…", x: card.minX + 22, y: card.minY + 44, size: 9, color: p.placeholder)

        // 译文行
        Typo.draw(lang == "en" ? "translation appears as you type" : "译文在这里实时出现",
                  x: card.minX + 14, y: card.minY + 74, size: 10, color: p.text)
        Typo.draw("Enter · ⌃Enter · Tab · Esc", x: card.minX + 14, y: card.minY + 98, size: 8, color: p.textFaint)

        // 右侧标注
        let notes: [String]
        if kind == .cardAnatomy {
            notes = [lang == "en" ? "① badge row + close" : "① 徽章行 + 关闭",
                     lang == "en" ? "② rounded input box" : "② 圆角输入框",
                     lang == "en" ? "③ live translation" : "③ 实时译文",
                     lang == "en" ? "④ hint row" : "④ 提示行"]
        } else {
            notes = [lang == "en" ? "target window" : "目标窗口",
                     lang == "en" ? "card snaps above" : "浮层贴在窗口上方",
                     lang == "en" ? "width follows" : "宽度跟随窗口"]
        }
        var ny = card.minY + 16
        for note in notes {
            Typo.draw(note, x: card.maxX + 24, y: ny, size: 10, color: p.textDim)
            ny += 20
        }

        // 吸附示意：目标窗口轮廓
        if kind == .snap {
            let win = CGRect(x: card.minX, y: card.minY + 60, width: card.width, height: 86)
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            let wp = NSBezierPath(roundedRect: win, xRadius: 8, yRadius: 8)
            wp.lineWidth = 1
            wp.stroke()
            p.accent.withAlphaComponent(0.7).setFill()
            NSBezierPath(rect: CGRect(x: win.minX, y: win.minY, width: win.width, height: 3)).fill()
        }
    }
}
