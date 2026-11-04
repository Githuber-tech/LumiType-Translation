import AppKit
import Carbon.HIToolbox
import LumiTypeCore

/// 组合键：内部用「Carbon 修饰符 + 虚拟键码」表示，
/// 对外仍用 Windows 版的字符串写法（`Alt+Y` / `Ctrl+Alt+Y`），
/// 这样 Windows 的 settings.json 拷过来直接生效。
struct KeyCombo: Equatable {
    var carbonModifiers: UInt32
    var keyCode: UInt32
    /// 规范化字符串，写回配置用
    var canonical: String

    /// 展示用（菜单/输入框）：⌃⌥⇧⌘ 加键名
    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyMap.name(for: Int(keyCode))
    }
}

enum KeyMap {

    /// 键名 → 虚拟键码（名字沿用 Windows 版写法：A-Z / 0-9 / F1-F12 / 方向键 …）
    static let nameToCode: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
        "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
        "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
        "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4,
        "F5": kVK_F5, "F6": kVK_F6, "F7": kVK_F7, "F8": kVK_F8,
        "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
        "Space": kVK_Space, "Left": kVK_LeftArrow, "Right": kVK_RightArrow,
        "Up": kVK_UpArrow, "Down": kVK_DownArrow,
        "Home": kVK_Home, "End": kVK_End, "PageUp": kVK_PageUp, "PageDown": kVK_PageDown,
        "Delete": kVK_Delete, "Insert": kVK_Help
    ]

    static func name(for code: Int) -> String {
        if let hit = nameToCode.first(where: { $0.value == code }) { return hit.key }
        return "?"
    }

    /// 解析 `Ctrl+Alt+Y` / `alt+y` / `⌥Y` 等写法。
    /// 不合法（无修饰键或未知键名）返回 nil —— 由调用方给出 `hk_err_mod` / `hk_err_key`。
    static func parse(_ raw: String) -> KeyCombo? {
        let text = raw.replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: "+").map(String.init)
        var mods: UInt32 = 0
        var keyName: String?
        for part in parts {
            switch part.lowercased() {
            case "ctrl", "control", "⌃": mods |= UInt32(controlKey)
            case "alt", "option", "⌥": mods |= UInt32(optionKey)
            case "shift", "⇧": mods |= UInt32(shiftKey)
            case "win", "cmd", "command", "meta", "⌘": mods |= UInt32(cmdKey)
            default:
                if part.hasPrefix("⌃") { mods |= UInt32(controlKey); keyName = String(part.dropFirst()) }
                else if part.hasPrefix("⌥") { mods |= UInt32(optionKey); keyName = String(part.dropFirst()) }
                else if part.hasPrefix("⇧") { mods |= UInt32(shiftKey); keyName = String(part.dropFirst()) }
                else if part.hasPrefix("⌘") { mods |= UInt32(cmdKey); keyName = String(part.dropFirst()) }
                else { keyName = part }
            }
        }
        guard mods != 0 else { return nil }
        guard let name = keyName?.uppercased(), !name.isEmpty else { return nil }
        // 单字母/数字/F 键统一大写
        let normalized = name.count == 1 ? name : name.prefix(1) + name.dropFirst().lowercased()
        guard let code = nameToCode[normalized] ?? nameToCode[name] else { return nil }
        return KeyCombo(carbonModifiers: mods, keyCode: UInt32(code), canonical: canonical(mods, name))
    }

    /// 规范化字符串：固定顺序 Ctrl+Alt+Shift+Win
    static func canonical(_ mods: UInt32, _ keyName: String) -> String {
        var parts: [String] = []
        if mods & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if mods & UInt32(optionKey) != 0 { parts.append("Alt") }
        if mods & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if mods & UInt32(cmdKey) != 0 { parts.append("Win") }
        parts.append(keyName.uppercased())
        return parts.joined(separator: "+")
    }

    /// 从 AppKit 事件生成组合键（快捷键录入用）
    static func from(event: NSEvent) -> KeyCombo? {
        var mods: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        let code = Int(event.keyCode)
        // Esc 用来取消录入，不能作为热键
        if code == kVK_Escape { return nil }
        guard mods != 0 else { return nil }
        let name = KeyMap.name(for: code)
        guard name != "?" else { return nil }
        return KeyCombo(carbonModifiers: mods, keyCode: UInt32(code), canonical: canonical(mods, name))
    }
}

/// 全局热键。macOS 没有 `RegisterHotKey`，对应物是 Carbon 的
/// `RegisterEventHotKey` —— 至今仍可用且不触发「输入监控」授权，
/// 是 App Store 之外最干净的选择。
final class HotkeyManager {

    static let shared = HotkeyManager()

    enum Action: UInt32 {
        case toggle = 1
        case clipboard = 2
    }

    var onAction: ((Action) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    private init() {}

    /// 安装唯一的 Carbon 事件处理器（只装一次）
    func install() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: hkID.id) {
                DispatchQueue.main.async { manager.onAction?(action) }
            }
            return noErr
        }, 1, &spec, selfPtr, &handler)
    }

    /// 注册（或重注册）一个热键。冲突时返回 false —— 对应 `hk_err_busy`。
    @discardableResult
    func register(_ action: Action, combo: KeyCombo) -> Bool {
        if let ref = refs[action.rawValue] {
            UnregisterEventHotKey(ref)
            refs.removeValue(forKey: action.rawValue)
        }
        var hotKeyID = EventHotKeyID(signature: OSType(0x4C4D5459), id: action.rawValue)  // 'LMTY'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.shared.info("hotkey register failed action=\(action.rawValue) combo=\(combo.canonical) status=\(status)")
            return false
        }
        refs[action.rawValue] = ref
        Log.shared.info("hotkey registered \(action) \(combo.canonical)")
        return true
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    /// 按当前配置重新注册全部热键，返回每一项的成功与否
    func apply(toggle: String, clipboard: String) -> (toggle: Bool, clipboard: Bool) {
        var okToggle = false, okClipboard = false
        if let combo = KeyMap.parse(toggle) {
            okToggle = register(.toggle, combo: combo)
        }
        if let combo = KeyMap.parse(clipboard) {
            okClipboard = register(.clipboard, combo: combo)
        }
        return (okToggle, okClipboard)
    }
}
