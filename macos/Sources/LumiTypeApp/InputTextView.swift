import AppKit

/// 浮层里的输入框。
///
/// Windows 版是宿主一个真实 TextBox 子窗口；Mac 侧用 NSTextView，
/// 这样中文输入法、候选窗、⌘A/⌘V、撤销全部免费可用 ——
/// 这些行为如果手写 KeyDown 模拟，输入法一定会出问题。
final class InputTextView: NSTextView {

    enum Command {
        case enter
        case ctrlEnter
        case tab
        case escape
    }

    var onCommand: ((Command) -> Void)?
    /// 换行/删除等普通编辑后回调，用于重排卡片
    var onEdited: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 输入法组合中（marked text）时一律交给输入法：
        // 拼音候选窗里的回车是「选词」，Esc 是「取消组合」，
        // 这里若抢走就会变成「提交译文 / 关闭浮层」——中文输入必踩的坑。
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 36, 76:                       // Return / 小键盘 Enter
            if flags.contains(.control) {
                onCommand?(.ctrlEnter)
            } else if flags.contains(.shift) {
                insertNewline(nil)          // Shift+Enter 换行（V5.7.0）
                onEdited?()
            } else {
                onCommand?(.enter)
            }
        case 48:                            // Tab：切换引擎
            onCommand?(.tab)
        case 53:                            // Esc：关闭浮层
            onCommand?(.escape)
        default:
            super.keyDown(with: event)
        }
    }

    /// 输入法组合中的回车不能当提交（否则选词会被吞掉）
    override func didChangeText() {
        super.didChangeText()
        onEdited?()
    }
}
