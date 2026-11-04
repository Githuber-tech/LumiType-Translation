import Foundation

/// 首选项「更新日志」页的数据源。
///
/// 原版把这个列表编译进了程序集（`ChangelogAuto.Entries` / `EntriesEn`），
/// 这里从二进制里读出 69 条原样内置，保证更新日志页内容与 Windows 版逐条一致。
public enum Changelog {

    public struct Entry: Sendable, Equatable {
        public let version: String
        /// 更新级别：大更新 / 中更新 / 小更新…（空字符串表示原版未标注）
        public let kind: String
        public let title: String
        /// 原版的英文译文，早期版本可能不存在
        public let titleEn: String?

        public init(version: String, kind: String, title: String, titleEn: String?) {
            self.version = version
            self.kind = kind
            self.title = title
            self.titleEn = titleEn
        }
    }

    /// macOS 版自身的 2.0.0 条目。
    /// 它**不在** `ChangelogBuiltIn` 里 —— 那个数组是从 exe 原样提取的 Windows 历史，
    /// 手改会破坏「逐条一致」这一验收项。这里单列一条，排在继承来的历史之前。
    public static let macEntry = Entry(
        version: "2.0.0",
        kind: "macOS 原生版",
        title: "macOS 原生版首发：菜单栏浮层、吸附、四页首选项、通用二进制",
        titleEn: "First macOS release: menu-bar overlay, snapping, four preference pages, a universal binary"
    )

    /// 全部条目：macOS 2.0.0 + Windows 历史（按版本号降序）
    public static let all: [Entry] = [macEntry] + ChangelogBuiltIn.entries

    public static var latest: Entry? { all.first }

    /// 按语言取标题；英文缺失时回退中文（与原版行为一致）
    public static func title(_ e: Entry, _ uiLang: String) -> String {
        if uiLang == "en", let en = e.titleEn, !en.isEmpty { return en }
        return e.title
    }

    /// 更新级别徽标的英文映射。
    /// 原版的级别字符串在中英两套数组里各存一份，这里按已知取值做确定性映射。
    public static func kindLabel(_ kind: String, _ uiLang: String) -> String {
        if kind.isEmpty { return "" }
        guard uiLang == "en" else { return kind }
        switch kind {
        case "大更新": return "Major update"
        case "中更新": return "Medium update"
        case "小更新": return "Minor update"
        case "小更新，严重修复": return "Small update, critical fix"
        case "小更新·热修复": return "Minor update, hotfix"
        case "macOS 原生版": return "macOS native release"
        default: return kind
        }
    }

    /// 取最近 n 条（界面默认只展示到窗口高度）
    public static func recent(_ n: Int) -> [Entry] {
        Array(all.prefix(max(0, n)))
    }
}
