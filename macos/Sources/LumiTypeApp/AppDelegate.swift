import AppKit
import LumiTypeCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    static private(set) var shared: AppDelegate!

    private let statusMenu = StatusMenu()
    private var overlays: [OverlayController] = []
    private var active: OverlayController?
    private var prefs: PreferencesWindowController?
    private var updateTimer: Timer?
    private var lockFD: Int32 = -1
    private let updater = Updater()

    private var store: ConfigStore { .shared }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Log.shared.info("LumiType \(Product.versionText) (macOS) starting, bundle=\(Bundle.main.bundleIdentifier ?? "dev")")

        waitForPredecessorIfRestarting()

        guard acquireSingleInstanceLock() else {
            presentMessage(store.t("msg_running"), info: "LumiType \(Product.versionText)")
            NSApp.terminate(nil)
            return
        }

        // 首次运行：把默认配置落到磁盘，用户能直接打开看字段
        if !FileManager.default.fileExists(atPath: AppPaths.configFile.path) {
            try? store.config.save()
        }

        buildStatusMenu()
        installHotkeys()
        observeConfig()

        // 没有任何引擎 Key 时直接把首选项摆到面前 —— 否则用户按热键只会看到报错
        if store.config.configuredProviders.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showPreferences()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates(silent: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.prewarmConnection()
        }

        if !PasteService.hasAccessibility,
           ProcessInfo.processInfo.environment["LUMITYPE_NO_TCC_PROMPT"] == nil {
            // 首次引导：不阻塞启动，但必须让用户知道为什么粘贴不了
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                PasteService.requestAccessibility()
            }
        }

        // --demo "<text>"：启动后直接摆一个浮层，用于验收与截图
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--demo") {
            let text = index + 1 < args.count ? args[index + 1] : "我们明天下午三点开会，请提前准备报价单。"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openOverlayFromMouse(text, force: true)
            }
            // --demo-shot <png>：1.6 秒后把真实窗口渲染成 PNG 再退出（自检用）
            if let shotIndex = args.firstIndex(of: "--demo-shot"), shotIndex + 1 < args.count {
                let path = args[shotIndex + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    self?.active?.captureSnapshot(to: path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.terminate(nil)
                    }
                }
            }
        } else if args.contains("--prefs") || args.contains("--prefs-shot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPreferences()
            }
            // --prefs-shot <png>：首选项窗口渲染成 PNG 后退出（自检用）
            if let shotIndex = args.firstIndex(of: "--prefs-shot"), shotIndex + 1 < args.count {
                let path = args[shotIndex + 1]
                let tabIndex = args.firstIndex(of: "--prefs-tab").flatMap { i -> Int? in
                    i + 1 < args.count ? Int(args[i + 1]) : nil
                } ?? 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.prefs?.selectTab(tabIndex)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.prefs?.captureSnapshot(to: path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
        for overlay in overlays { overlay.close() }
        overlays.removeAll()
        store.save()
        if lockFD >= 0 { close(lockFD) }
        Log.shared.info("LumiType terminated")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - 单实例

    /// `--restart-after <pid>`：重启时新实例先等旧进程完全退出，再去抢单实例锁
    /// 与全局热键。否则旧进程还占着热键，新实例注册失败会弹「组合键被占用」。
    private func waitForPredecessorIfRestarting() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--restart-after"), index + 1 < args.count,
              let pid = Int32(args[index + 1]), pid > 0 else { return }
        var waited = 0
        while kill(pid, 0) == 0 && waited < 60 {     // 最多等 6 秒
            usleep(100_000)
            waited += 1
        }
        Log.shared.info("restart: predecessor \(pid) gone after \(waited * 100) ms")
    }

    private func acquireSingleInstanceLock() -> Bool {
        let path = AppPaths.ensure(AppPaths.support).appendingPathComponent("app.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    // MARK: - 菜单栏

    private func buildStatusMenu() {
        statusMenu.onOpen = { [weak self] in self?.openOverlayFromMouse() }
        statusMenu.onClipboard = { [weak self] in self?.translateClipboard() }
        statusMenu.onPrefs = { [weak self] in self?.showPreferences() }
        statusMenu.onCheckUpdates = { [weak self] in self?.checkForUpdates(silent: false) }
        statusMenu.onToggleAutoStart = { [weak self] in self?.toggleAutoStart() }
        statusMenu.onRestart = { [weak self] in self?.restart() }
        statusMenu.onAbout = { [weak self] in self?.showAbout() }
        statusMenu.onQuit = { NSApp.terminate(nil) }
    }

    private var appliedHotkeys = ""

    private func observeConfig() {
        appliedHotkeys = store.config.hotkeyToggle + "|" + store.config.hotkeyClipboard
        store.observe { [weak self] cfg in
            guard let self else { return }
            self.statusMenu.refresh()
            // 拖动透明度滑杆会每秒触发十几次配置变更；
            // 只有热键真的变了才重新注册（否则会反复抢注册、甚至弹冲突提示）。
            let signature = cfg.hotkeyToggle + "|" + cfg.hotkeyClipboard
            if signature != self.appliedHotkeys {
                self.appliedHotkeys = signature
                self.installHotkeys()
            }
            self.overlays.forEach { $0.loadAppearance() }
        }
    }

    // MARK: - 热键

    private func installHotkeys() {
        let cfg = store.config
        HotkeyManager.shared.install()
        HotkeyManager.shared.onAction = { [weak self] action in
            switch action {
            case .toggle: self?.openOverlayFromMouse()
            case .clipboard: self?.translateClipboard()
            }
        }
        let result = HotkeyManager.shared.apply(toggle: cfg.hotkeyToggle, clipboard: cfg.hotkeyClipboard)
        if !result.toggle || !result.clipboard {
            Log.shared.info("hotkey conflict toggle=\(result.toggle) clipboard=\(result.clipboard)")
            presentMessage(store.t("hk_err_busy"), info: "\(cfg.hotkeyToggle) / \(cfg.hotkeyClipboard)")
        }
    }

    // MARK: - 浮层

    /// 唤出：贴着鼠标当前位置 + 配置偏移（与 Windows 的 `Cursor.Position` 一致）
    func openOverlayFromMouse(_ initialText: String? = nil, force: Bool = false) {
        // 没有 Key 时先给首选项，而不是弹一个必然失败的浮层
        if store.config.configuredProviders.isEmpty && !force {
            showPreferences()
            return
        }
        let controller = OverlayController()
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.overlays.removeAll { $0 === controller }
            if self.active === controller { self.active = nil }
        }
        overlays.append(controller)
        active = controller
        controller.show(near: NSEvent.mouseLocation)
        if let initialText, !initialText.isEmpty {
            controller.acceptExternalText(initialText)
        }
    }

    func translateClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        openOverlayFromMouse(text)
    }

    // MARK: - 首选项 / 关于

    func showPreferences() {
        if prefs == nil {
            prefs = PreferencesWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        prefs?.showWindow(nil)
    }

    private func showAbout() {
        let credits = store.t("about_credit") + "\n" + Product.repositoryURL
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "LumiType 灵译",
            .applicationVersion: Product.versionText,
            .version: "macOS",
            .credits: NSAttributedString(string: credits, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 开机启动 / 重启

    private func toggleAutoStart() {
        let next = !store.config.autoStart
        let ok = AutoStart.set(next)
        if ok {
            store.update { $0.autoStart = next }
        } else {
            presentMessage(store.t("upd_installfail", ["LaunchAgent"]), info: nil)
        }
        statusMenu.refresh()
    }

    func restart() {
        store.save()
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else {
            // 开发期：直接重启可执行文件
            let path = CommandLine.arguments.first ?? ""
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            try? p.run()
            NSApp.terminate(nil)
        }
    }

    /// V6.2.0「启动预热」：先建好 TCP+TLS，让第一句翻译不必付握手钱。
    /// 用 `GET /v2/usage` 而不是翻译接口 —— 不产生翻译计费，只建立连接。
    private func prewarmConnection() {
        let cfg = store.config
        guard (Provider(rawValue: cfg.provider) ?? .deepl) == .deepl,
              !cfg.effectiveDeepLKey.isEmpty else { return }
        let base = cfg.baseUrl.isEmpty ? DeepLClient.defaultBase : cfg.baseUrl
        let trimmed = base.hasSuffix("/") ? base : base + "/"
        guard let url = URL(string: trimmed + "usage") else { return }
        var request = URLRequest(url: url)
        request.setValue("DeepL-Auth-Key \(cfg.effectiveDeepLKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeepLClient.userAgent, forHTTPHeaderField: "User-Agent")
        TranslationService.session(for: cfg).dataTask(with: request) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.shared.debug("prewarm code=\(code) err=\(error?.localizedDescription ?? "-")")
        }.resume()
    }

    // MARK: - 更新

    private func checkForUpdates(silent: Bool) {
        updater.check(silent: silent) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let info):
                self.statusMenu.updateVersion = info?.version
                self.statusMenu.refresh()
                if let info, !silent {
                    self.promptInstall(info)
                }
            case .failure(let error):
                if !silent {
                    var message = self.store.t("upd_fail", [error.localizedDescription])
                    if let updateError = error as? Updater.UpdateError, updateError.isNoSource {
                        message = self.store.t("upd_nosrc")
                    }
                    self.presentMessage(message, info: nil)
                }
            }
        }
    }

    private func promptInstall(_ info: Updater.Info) {
        let alert = NSAlert()
        alert.messageText = store.t("upd_title", [info.version])
        alert.informativeText = info.notes.isEmpty ? store.t("upd_body") : info.notes
        alert.addButton(withTitle: store.t("upd_item", [info.version]))
        alert.addButton(withTitle: store.t("fb_cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            updater.install(info) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    var message = self.store.t("upd_err", [error.localizedDescription])
                    if let updateError = error as? Updater.UpdateError, updateError.isShaMismatch {
                        message = self.store.t("upd_sha")
                    }
                    self.presentMessage(message, info: nil)
                }
            }
        }
    }

    // MARK: - 提示

    func presentMessage(_ text: String, info: String?) {
        let alert = NSAlert()
        alert.messageText = text
        if let info { alert.informativeText = info }
        alert.alertStyle = .informational
        alert.runModal()
    }
}
