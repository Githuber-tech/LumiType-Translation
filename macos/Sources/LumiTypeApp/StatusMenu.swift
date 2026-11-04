import AppKit
import LumiTypeCore

/// 菜单栏常驻项。对应原版托盘菜单的 8 项结构：
/// 打开浮层 / 剪贴板翻译 / ─ / 首选项 / 检查更新 / 开机启动 / ─ / 重启 / 关于 / ─ / 退出
final class StatusMenu: NSObject, NSMenuDelegate {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    var onOpen: (() -> Void)?
    var onClipboard: (() -> Void)?
    var onPrefs: (() -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onToggleAutoStart: (() -> Void)?
    var onRestart: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    /// 有新版本时菜单项变成「一键更新到 V{0}」
    var updateVersion: String?

    override init() {
        super.init()
        if let button = item.button {
            button.image = IconArt.statusImage()
            button.imagePosition = .imageOnly
            button.toolTip = ConfigStore.shared.t("tray_tip", [Product.versionText])
        }
        menu.delegate = self
        item.menu = menu
        rebuild()
    }

    func refresh() {
        item.button?.toolTip = ConfigStore.shared.t("tray_tip", [Product.versionText])
        rebuild()
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    private func rebuild() {
        let store = ConfigStore.shared
        menu.removeAllItems()

        menu.addItem(makeItem(store.t("tray_open"), #selector(open)))
        menu.addItem(makeItem(store.t("tray_clip"), #selector(clipboard)))
        menu.addItem(.separator())
        menu.addItem(makeItem(store.t("tray_prefs"), #selector(prefs), key: ","))

        if let version = updateVersion {
            menu.addItem(makeItem(store.t("upd_item", [version]), #selector(checkUpdates)))
        } else {
            menu.addItem(makeItem(store.t("tray_check"), #selector(checkUpdates)))
        }

        let auto = makeItem(store.t("tray_autostart"), #selector(toggleAutoStart))
        auto.state = store.config.autoStart ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        menu.addItem(makeItem(store.t("tray_restart"), #selector(restart)))
        menu.addItem(makeItem(store.t("tray_about"), #selector(about)))
        menu.addItem(.separator())
        menu.addItem(makeItem(store.t("tray_exit"), #selector(quit)))
    }

    // MARK: - 动作

    @objc private func open() { onOpen?() }
    @objc private func clipboard() { onClipboard?() }
    @objc private func prefs() { onPrefs?() }
    @objc private func checkUpdates() { onCheckUpdates?() }
    @objc private func toggleAutoStart() { onToggleAutoStart?() }
    @objc private func restart() { onRestart?() }
    @objc private func about() { onAbout?() }
    @objc private func quit() { onQuit?() }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }
}
