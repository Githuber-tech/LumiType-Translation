import AppKit
import CoreGraphics

/// 吸附目标发现与跟随。
///
/// Windows 版靠 `EnumWindows` + 进程名白名单；macOS 对应物是
/// `CGWindowListCopyWindowInfo`（不需要屏幕录制授权即可拿到窗口**框**，
/// 只有像素内容才需要授权）。
final class SnapMonitor {

    struct Target {
        let number: Int
        let pid: pid_t
        let name: String
        let bundleID: String
        let frame: CGRect        // Cocoa 坐标（左下原点）
    }

    static let shared = SnapMonitor()

    /// 白名单：Windows 版按进程名，macOS 按 bundle id。
    /// 原版 18 项 → 这里 20 项（桌面端没有 TIM/记事本同名进程，换成 Notes/Safari）。
    static let whitelist: [String: String] = [
        "com.tencent.xinWeChat": "微信",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.tencent.qq": "QQ",
        "com.bytedance.macos.feishu": "飞书",
        "com.electron.lark": "Lark",
        "com.alibaba.DingTalkMac": "钉钉",
        "com.apple.Notes": "备忘录",
        "com.apple.Safari": "Safari",
        "com.mailbird.desktop": "Mailbird",
        "com.google.Chrome": "Chrome",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
        "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.microsoft.VSCode": "VS Code",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "notion.id": "Notion",
        "com.microsoft.teams2": "Teams",
        "com.spotify.client": "Spotify",
        "com.figma.Desktop": "Figma"
    ]

    private var mainScreenHeight: CGFloat {
        (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main)?.frame.height ?? 1080
    }

    func cocoaRect(fromCG rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 当前所有「可作为吸附目标」的窗口
    func candidates() -> [Target] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var out: [Target] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value != myPID,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let pid = pidNumber.int32Value
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? ""
            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? app?.localizedName ?? ""
            let displayName = SnapMonitor.whitelist[bundleID] ?? ownerName

            // 只认白名单里的应用：Windows 版也是同样的收敛策略，
            // 否则任何窗口边缘都能吸，用户会误触。
            guard SnapMonitor.whitelist[bundleID] != nil else { continue }
            guard cgRect.width >= 240, cgRect.height >= 160 else { continue }

            out.append(Target(number: number, pid: pid, name: displayName,
                              bundleID: bundleID, frame: cocoaRect(fromCG: cgRect)))
        }
        return out
    }

    /// 拖动结束时找最近的边：命中返回 (目标, 边)，边 0 = 贴在窗口上方，1 = 下方
    func find(for card: CGRect, threshold: CGFloat = 44) -> (Target, Int)? {
        var best: (Target, Int, CGFloat)?
        for target in candidates() {
            let horizontalOverlap = min(card.maxX, target.frame.maxX) - max(card.minX, target.frame.minX)
            guard horizontalOverlap > 40 else { continue }

            let dTop = abs(card.minY - target.frame.minY)
            if dTop <= threshold, best == nil || dTop < best!.2 {
                best = (target, 0, dTop)
            }
            let dBottom = abs(card.maxY - target.frame.maxY)
            if dBottom <= threshold, best == nil || dBottom < best!.2 {
                best = (target, 1, dBottom)
            }
        }
        guard let hit = best else { return nil }
        return (hit.0, hit.1)
    }

    /// 吸附后跟随：按窗口号取最新框（窗口关闭返回 nil）
    func frame(ofWindow number: Int) -> CGRect? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let list = CGWindowListCopyWindowInfo(options, CGWindowID(number)) as? [[String: Any]],
              let info = list.first,
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              cgRect.width > 1, cgRect.height > 1
        else { return nil }
        return cocoaRect(fromCG: cgRect)
    }

    func app(for target: Target) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: target.pid)
    }
}
