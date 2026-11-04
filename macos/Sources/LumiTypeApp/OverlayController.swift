import AppKit
import LumiTypeCore

/// 无边框浮层窗口。
/// `canBecomeKey` 必须为 true —— 否则输入框收不到键盘事件（这是
/// Windows 版 `WS_EX_NOACTIVATE` 与 macOS 语义不同的地方：
/// Mac 上「不抢焦点」和「能打字」不能同时成立，我们选择后者，
/// 提交后再把焦点还给原应用）。
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 一个浮层实例：窗口 + 视图 + 翻译状态机。
/// 对应 `OverlayInstance`：每次唤出都是独立实例，各自维护输入与译文。
final class OverlayController {

    let panel: OverlayPanel
    let view: OverlayView
    private let backdrop = NSVisualEffectView()

    private var model = CardModel()
    private var generation = 0
    private var debounce: DispatchWorkItem?
    private var pulseTimer: Timer?
    private var followTimer: Timer?
    private var commitGeneration = 0

    /// 唤出前的应用 —— Enter 之后把译文送回它
    private var previousApp: NSRunningApplication?
    private var snapTarget: SnapMonitor.Target?
    private var snapEdge = 0
    private var anchorTopLeft: CGPoint = .zero

    var onClose: (() -> Void)?

    private var store: ConfigStore { .shared }
    private var cfg: Config { store.config }
    private var lang: String { store.uiLang }

    // MARK: - 初始化

    init() {
        panel = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 180),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 180))
        root.wantsLayer = true
        root.layer?.backgroundColor = .clear

        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 14
        backdrop.layer?.masksToBounds = true
        root.addSubview(backdrop)

        view = OverlayView(frame: root.bounds)
        root.addSubview(view)
        panel.contentView = root

        wire()
        loadAppearance()
    }

    private func wire() {
        view.onSizeChange = { [weak self] size in
            self?.resize(to: size)
        }
        view.onTextChange = { [weak self] text in
            self?.handleTextChange(text)
        }
        view.onEdited = { [weak self] in
            self?.refreshInputLines()
        }
        view.onKey = { [weak self] cmd in
            self?.handleKey(cmd)
        }
        view.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .close: self.close()
            case .unpin: self.unsnap()
            case .note: self.openNotepad()
            case .swap: self.swapLanguages()
            }
        }
        view.onWidthChange = { [weak self] width in
            guard let self else { return }
            self.model.widthOverride = width
            self.view.model = self.model
            self.keepTopLeft()
        }
        view.onDragBegin = { [weak self] in
            self?.snapPreview(nil)
        }
        view.onDragMove = { [weak self] in
            self?.updateSnapPreview()
        }
        view.onDragEnd = { [weak self] in
            self?.evaluateSnap()
        }
    }

    // MARK: - 外观

    func loadAppearance() {
        let c = cfg
        model.theme = Skin.from(c.theme)
        model.glassOpacity = c.glassOpacity
        model.showSource = c.showSource
        model.showHints = c.showHints
        model.showPills = c.showPills
        model.showLatency = c.showLatency
        model.hints = hintsForState()
        model.fontScale = CGFloat(c.fontScale)
        // 毛玻璃材质跟着皮肤走：深色用 hudWindow（暗玻璃），
        // 浅色/主题色用 popover（浅色玻璃）。否则浅色皮肤会被暗底拉灰。
        let skin = Skin.from(c.theme)
        backdrop.material = skin == .glassDark ? .hudWindow : .popover
        backdrop.appearance = NSAppearance(named: skin == .glassDark ? .darkAqua : .aqua)
        view.maxWidth = CGFloat(c.maxWidth)
        view.maxHeight = max(320, (NSScreen.main?.visibleFrame.height ?? 900) - 80)
        view.model = model
        refreshLabels(for: view.inputString)
    }

    private func hintsForState() -> String {
        if model.pinned { return store.t("hints_pinned") }
        return store.t(cfg.configuredProviders.count > 1 ? "hints_model" : "hints_free")
    }

    // MARK: - 显示

    /// `point` 是 Cocoa 全局坐标里「光标位置」，卡片出现在它右下方。
    func show(near point: CGPoint) {
        previousApp = NSWorkspace.shared.frontmostApplication
        loadAppearance()

        let size = CGSize(width: view.layout.winW, height: view.layout.winH)
        let topLeft = CGPoint(x: point.x + CGFloat(cfg.offsetX),
                              y: point.y - CGFloat(cfg.offsetY))
        anchorTopLeft = topLeft
        let origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        view.focusInput()

        clampIntoWorkArea()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
        Log.shared.debug("overlay shown at \(anchorTopLeft)")
    }

    private func resize(to size: CGSize) {
        guard panel.frame.size != size else { return }
        keepTopLeft(size: size)
    }

    /// 卡片高度会随内容变化，锚点保持左上角不动（向下生长）
    private func keepTopLeft(size: CGSize? = nil) {
        let s = size ?? panel.frame.size
        let origin = CGPoint(x: anchorTopLeft.x, y: anchorTopLeft.y - s.height)
        panel.setFrame(CGRect(origin: origin, size: s), display: true)
        layoutBackdrop()
    }

    private func layoutBackdrop() {
        backdrop.frame = view.layout.cardRect
        backdrop.layer?.cornerRadius = view.layout.radius
    }

    private func clampIntoWorkArea() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        let wa = screen.visibleFrame
        var frame = panel.frame
        if frame.maxX > wa.maxX { frame.origin.x = wa.maxX - frame.width }
        if frame.minX < wa.minX { frame.origin.x = wa.minX }
        if frame.minY < wa.minY { frame.origin.y = wa.minY }
        if frame.maxY > wa.maxY { frame.origin.y = wa.maxY - frame.height }
        panel.setFrame(frame, display: true)
        anchorTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }

    // MARK: - 输入

    /// 外部写入文本（剪贴板翻译、托盘菜单）后立即走一次翻译流程
    func acceptExternalText(_ text: String) {
        view.setText(text)
        handleTextChange(text)
        view.focusInput()
    }

    private func handleTextChange(_ text: String) {
        model.source = text
        refreshLabels(for: text)
        if snapTarget == nil { model.status = "" }
        refreshInputLines()

        guard cfg.realtime, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count >= cfg.minChars else { return }
        scheduleTranslation()
    }

    private func refreshInputLines() {
        let width = view.layout.inputRect.width
        let lines = max(1, Typo.wrap(view.inputString, width: width, size: view.layout.fsSrc).count)
        if lines != model.inputLines {
            model.inputLines = lines
            view.model = model
            keepTopLeft()
        } else {
            view.model = model
        }
    }

    private func refreshLabels(for text: String) {
        model.engineLabel = LanguageResolver.engineLabel(cfg)
        model.sourceLabel = LanguageResolver.resolveSource(cfg, text: text)
        model.targetLabel = LanguageResolver.resolveTarget(cfg, text: text)
        model.hints = hintsForState()
        view.model = model
        layoutBackdrop()
    }

    /// V6.2.0 的出发时机：已经说了整句（句末标点/换行）→ 220 ms 就发；
    /// 没有句末标点 → 等 2.5 s，避免「逗号一停就翻半句」的碎片问题。
    /// 原版用 `SystemInformation.CaretBlinkTime×3` 作常规停手时间，
    /// Mac 没有这个系统量，取同量级的 2.5 s（V5.9.0 的 LongSettleMs）。
    static func settleDelay(for text: String) -> TimeInterval {
        isSentenceEnd(text) ? 0.22 : 2.5
    }

    static func isSentenceEnd(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "。！？.!?…\n".contains(last)
    }

    private func scheduleTranslation() {
        debounce?.cancel()
        let text = view.inputString
        let work = DispatchWorkItem { [weak self] in
            self?.translate(text: text, commitAfter: false)
        }
        debounce = work
        model.status = store.t("st_typing")
        model.statusTone = .dim
        view.model = model
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay(for: text), execute: work)
    }

    // MARK: - 翻译

    private func translate(text: String, commitAfter: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        generation += 1
        let gen = generation
        // 提交路径单独计数，避免防抖请求把提交结果判成过期（V5.9.0）
        if commitAfter { commitGeneration += 1 }
        let commitGen = commitGeneration

        model.waiting = true
        model.streaming = true
        model.error = false
        model.warning = ""
        model.result = ""
        model.resultFor = ""
        model.status = store.t("st_translating")
        model.statusTone = .dim
        model.inputFocus = true
        view.model = model
        startPulse()

        let snapshot = cfg
        let target = LanguageResolver.resolveTarget(snapshot, text: trimmed)
        let source: String
        switch Provider(rawValue: snapshot.provider) ?? .deepl {
        case .deepl: source = LanguageResolver.deepLSource(snapshot, text: trimmed)
        case .google: source = LanguageResolver.googleSource(snapshot, text: trimmed)
        case .llm: source = ""
        }
        let context = LanguageResolver.contextFor(target: target)
        let started = Date()
        let provider = Provider(rawValue: snapshot.provider) ?? .deepl

        Task { [weak self] in
            guard let self else { return }
            do {
                let service = TranslationService(config: snapshot,
                                                 cache: LruCache(capacity: snapshot.cacheSize, path: AppPaths.cache))
                let outcome = try await service.translate(trimmed, provider: provider,
                                                          source: source, target: target,
                                                          context: context)
                await MainActor.run {
                    guard commitAfter ? (commitGen == self.commitGeneration) : (gen == self.generation) else { return }
                    self.finish(outcome: outcome, source: trimmed, commitAfter: commitAfter)
                }
            } catch let error as EngineError {
                await MainActor.run {
                    guard commitAfter ? (commitGen == self.commitGeneration) : (gen == self.generation) else { return }
                    self.fail(error, commitAfter: commitAfter)
                }
            } catch {
                await MainActor.run {
                    guard commitAfter ? (commitGen == self.commitGeneration) : (gen == self.generation) else { return }
                    self.fail(EngineError("e_conn", detail: error.localizedDescription), commitAfter: commitAfter)
                }
            }
            _ = started
        }
    }

    private func finish(outcome: TranslationOutcome, source: String, commitAfter: Bool) {
        stopPulse()
        model.waiting = false
        model.streaming = false
        model.error = false
        model.result = outcome.text
        model.resultFor = source
        if outcome.cached {
            model.status = store.t("st_cache", ["\(outcome.charCount)"])
            model.statusTone = .ok
        } else {
            model.status = store.t("st_done", ["\(outcome.latencyMs)", "\(outcome.charCount)"])
            model.statusTone = .ok
        }
        view.model = model
        layoutBackdrop()

        if commitAfter {
            commit(outcome.text)
        }
    }

    private func fail(_ error: EngineError, commitAfter: Bool) {
        stopPulse()
        model.waiting = false
        model.streaming = false
        model.error = true
        model.result = ""
        model.status = store.t("st_fail")
        model.statusTone = .err
        model.warning = error.message(lang)
        view.model = model
        layoutBackdrop()
        Log.shared.info("translate failed: \(error.code) \(error.detail ?? "") commit=\(commitAfter)")
    }

    // MARK: - 键盘命令

    private func handleKey(_ cmd: InputTextView.Command) {
        switch cmd {
        case .escape:
            close()
        case .tab:
            cycleProvider()
        case .ctrlEnter:
            commit(view.inputString)
        case .enter:
            let source = view.inputString
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if !model.result.isEmpty && model.resultFor == source {
                commit(model.result)
            } else {
                // 结果不是这段文本的译文时先整段翻译，绝不把原文当译文粘出去（V5.9.0）
                translate(text: source, commitAfter: true)
            }
        }
    }

    private func cycleProvider() {
        let all = Provider.allCases
        let configured = cfg.configuredProviders
        guard configured.count > 1 else {
            model.status = store.t("st_engine_only")
            model.statusTone = .warn
            view.model = model
            return
        }
        let current = Provider(rawValue: cfg.provider) ?? .deepl
        let index = all.firstIndex(of: current) ?? 0
        var next = current
        for step in 1...all.count {
            let cand = all[(index + step) % all.count]
            if configured.contains(cand) { next = cand; break }
        }
        store.update { $0.provider = next.rawValue }
        model.engineLabel = next.shortLabel
        model.status = store.t("st_engine_now", [next.shortLabel])
        model.statusTone = .accent
        view.model = model
        let text = view.inputString
        if !text.isEmpty { translate(text: text, commitAfter: false) }
    }

    private func swapLanguages() {
        let source = cfg.sourceLang
        let target = cfg.targetLang
        store.update {
            $0.sourceLang = target
            $0.targetLang = source
            $0.pinSource = true
            $0.pinTarget = true
        }
        loadAppearance()
        let text = view.inputString
        if !text.isEmpty { translate(text: text, commitAfter: false) }
    }

    // MARK: - 提交

    /// 把文本送到「该去的地方」：吸附态 → 目标窗口；自由态 → 唤出前的应用
    private func commit(_ text: String) {
        guard !text.isEmpty else { return }
        let targetApp: NSRunningApplication?
        if model.pinned, let target = snapTarget {
            targetApp = SnapMonitor.shared.app(for: target)
        } else {
            targetApp = previousApp
        }

        PasteService.paste(text, to: targetApp) { [weak self] result in
            guard let self else { return }
            if result.needsPermission {
                self.model.warning = self.lang == "en"
                    ? "Copied to the clipboard — press ⌘V to insert. Grant Accessibility permission to insert automatically."
                    : "译文已复制到剪贴板，按 ⌘V 即可插入；在「系统设置 → 隐私与安全性 → 辅助功能」勾选 LumiType 可自动插入。"
                self.model.status = self.store.t("warn_fail")
                self.model.statusTone = .warn
                self.view.model = self.model
                return
            }
            self.resetAfterCommit()
        }
    }

    private func resetAfterCommit() {
        generation += 1
        debounce?.cancel()
        model.source = ""
        model.result = ""
        model.resultFor = ""
        model.warning = ""
        model.error = false
        model.waiting = false
        model.streaming = false
        model.status = ""
        model.inputLines = 1
        view.setText("")
        view.model = model
        keepTopLeft()
        stopPulse()
        if !model.pinned {
            // 自由态：焦点已经还给原应用，浮层保留但不再抢焦点
            panel.orderFrontRegardless()
        }
    }

    // MARK: - 吸附

    private func updateSnapPreview() {
        guard let frame = panelFrameInScreen() else { return }
        if let (target, edge) = SnapMonitor.shared.find(for: frame) {
            snapPreview((target, edge))
        } else {
            snapPreview(nil)
        }
    }

    private func snapPreview(_ hit: (SnapMonitor.Target, Int)?) {
        guard let hit else {
            if model.snapPreview {
                model.snapPreview = false
                model.snapLabel = ""
                view.model = model
                stopPulse()
            }
            return
        }
        model.snapPreview = true
        model.snapPreviewEdge = hit.1
        model.snapLabel = store.t("snap_release", [hit.0.name])
        view.model = model
        startPulse()
    }

    private func evaluateSnap() {
        defer {
            if !model.pinned {
                model.snapPreview = false
                model.snapLabel = ""
                view.model = model
                stopPulse()
            }
        }
        guard let frame = panelFrameInScreen(),
              let (target, edge) = SnapMonitor.shared.find(for: frame) else { return }
        snapTarget = target
        snapEdge = edge
        model.pinned = true
        model.snapPreview = false
        model.snapLabel = store.t("snapped", [target.name])
        model.hints = hintsForState()
        model.widthOverride = min(max(300, target.frame.width), CGFloat(cfg.maxWidth))
        view.model = model
        positionSnapped(animated: false)
        startFollow()
        Log.shared.info("snapped to \(target.bundleID) edge=\(edge)")
    }

    private func positionSnapped(animated: Bool) {
        guard let target = snapTarget else { return }
        let width = min(max(320, target.frame.width), CGFloat(cfg.maxWidth))
        if model.widthOverride != width {
            model.widthOverride = width
            view.model = model
        }
        let size = CGSize(width: view.layout.winW, height: view.layout.winH)
        let anchorY = snapEdge == 0 ? target.frame.maxY : target.frame.minY
        let originY = anchorY + view.layout.margin - size.height
        let origin = CGPoint(x: target.frame.minX - view.layout.margin, y: originY)
        let rect = CGRect(origin: origin, size: size)
        anchorTopLeft = CGPoint(x: rect.minX, y: rect.maxY)
        panel.setFrame(rect, display: !animated)
        layoutBackdrop()
    }

    private func startFollow() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.followTick()
        }
    }

    private var missingTicks = 0

    private func followTick() {
        guard model.pinned, let target = snapTarget else { return }
        guard let frame = SnapMonitor.shared.frame(ofWindow: target.number) else {
            missingTicks += 1
            if missingTicks >= 2 { close() }        // 目标窗口关闭 → 200ms 内自动关闭
            return
        }
        missingTicks = 0
        if frame != target.frame {
            snapTarget = SnapMonitor.Target(number: target.number, pid: target.pid, name: target.name,
                                            bundleID: target.bundleID, frame: frame)
            positionSnapped(animated: false)
        }
    }

    func unsnap() {
        followTimer?.invalidate()
        followTimer = nil
        snapTarget = nil
        model.pinned = false
        model.snapLabel = ""
        model.hints = hintsForState()
        model.widthOverride = 0
        view.model = model
        keepTopLeft()
    }

    private func panelFrameInScreen() -> CGRect? {
        let f = panel.frame
        // 转换到 CG 的「屏幕坐标」语义：直接用 Cocoa 坐标比较即可，
        // SnapMonitor 已统一转成 Cocoa。
        return CGRect(x: f.minX + view.layout.margin, y: f.minY + view.layout.margin,
                      width: view.layout.cardW, height: view.layout.cardH)
    }

    // MARK: - 动画

    private func startPulse() {
        guard pulseTimer == nil else { return }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.view.pulse += 0.1
            if !self.model.waiting && !self.model.streaming && !self.model.snapPreview {
                self.stopPulse()
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    // MARK: - 其它动作

    private func openNotepad() {
        let url = AppPaths.ensure(AppPaths.support).appendingPathComponent("scratch.txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    /// 自检用：把卡片渲染成 PNG。
    /// 只渲染 `OverlayView`（纯 Core Graphics 绘制），不碰背后的
    /// `NSVisualEffectView` —— 对含毛玻璃的整窗做离屏缓存会等窗口服务器，
    /// 没有屏幕录制授权时会卡死（实测）。
    func captureSnapshot(to path: String) {
        Snapshot.write(view, to: path)
    }

    func close() {
        stopPulse()
        followTimer?.invalidate()
        followTimer = nil
        debounce?.cancel()
        panel.orderOut(nil)
        panel.close()
        onClose?()
        Log.shared.debug("overlay closed")
    }
}
