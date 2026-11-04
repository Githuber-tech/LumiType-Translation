import AppKit

/// 把视图渲染成 PNG —— 自检与截图用，不需要屏幕录制授权。
///
/// 注意：**不要**对整个 `contentView` 调用 `cacheDisplay`。
/// 浮层里含 `NSVisualEffectView`（`.behindWindow` 混合），
/// 对整个窗口做离屏缓存会等窗口服务器回帧，在没有屏幕录制授权时
/// 会一直卡住——这是实测踩到的坑，所以这里只渲染纯绘制的子视图。
enum Snapshot {

    @discardableResult
    static func write(_ view: NSView, to path: String) -> Bool {
        guard view.bounds.width > 1, view.bounds.height > 1 else { return false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            Log.shared.info("snapshot written to \(path)")
            return true
        } catch {
            Log.shared.info("snapshot failed: \(error.localizedDescription)")
            return false
        }
    }
}
