import AppKit
import ApplicationServices

/// 「把译文送回原窗口」。
///
/// Windows 版是 `SetForegroundWindow` + `keybd_event(Ctrl+V)`；
/// macOS 对应物是 `NSRunningApplication.activate` + `CGEvent` 合成 ⌘V。
/// 关键差异：**合成键盘事件需要「辅助功能」授权**，未授权时降级为
/// 「只写剪贴板 + 提示用户自己按 ⌘V」，绝不静默失败。
enum PasteService {

    struct Result {
        var pasted: Bool
        var needsPermission: Bool
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// 首次需要时弹系统授权提示（只会弹一次，之后由用户去系统设置勾选）
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static var lastClipboard: String?
    private static var lastWritten: String?

    /// 写入剪贴板（保留上一次的文本，粘贴完成后恢复）
    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        if lastClipboard == nil { lastClipboard = pb.string(forType: .string) }
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastWritten = text
    }

    /// 只有在剪贴板里仍是**我们写进去的那段文字**时才还原。
    /// 如果用户在这期间自己复制了别的内容，绝不能抢回去覆盖掉。
    static func restoreClipboardIfNeeded() {
        defer { lastClipboard = nil; lastWritten = nil }
        guard let previous = lastClipboard else { return }
        guard let current = NSPasteboard.general.string(forType: .string),
              current == lastWritten else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previous, forType: .string)
    }

    /// 投递到指定应用：先激活它，再合成 ⌘V。
    /// `delay` 给窗口切换留出时间（原版是 250ms）。
    static func paste(_ text: String, to app: NSRunningApplication?,
                      delay: TimeInterval = 0.18,
                      completion: ((Result) -> Void)? = nil) {
        guard !text.isEmpty else { return }
        copyToClipboard(text)

        let trusted = hasAccessibility
        if let app, !app.isActive {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        guard trusted else {
            // 没有辅助功能授权：文本已经在剪贴板里，用户按 ⌘V 即可
            completion?(Result(pasted: false, needsPermission: true))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            postCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                restoreClipboardIfNeeded()
            }
            completion?(Result(pasted: true, needsPermission: false))
        }
    }

    /// 合成一次 ⌘V（keyCode 9 = V）
    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Log.shared.debug("posted Cmd+V")
    }
}
