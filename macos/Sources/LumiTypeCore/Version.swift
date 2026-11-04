import Foundation

/// 版本号，语义与原版 `LumiVersion` 一致。
///
/// 原版规则（来自二进制内字符串）：
/// `rule: Minor/Patch range 0..9; going past that carries into the next segment`
/// 即 minor 与 patch 上限为 9，超过则进位。
public struct LumiVersion: Comparable, CustomStringConvertible, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// 解析 "6.1.6" / "V6.1.6" / " 6.1.6 " 等形式；失败返回 nil
    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // 允许 "6.1.6.0" 这类四段写法，多余段忽略
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count >= 2, parts.count <= 4 else { return nil }
        let nums = parts.compactMap { Int($0) }
        guard nums.count == parts.count, nums.allSatisfy({ $0 >= 0 }) else { return nil }
        self.major = nums[0]
        self.minor = nums.count > 1 ? nums[1] : 0
        self.patch = nums.count > 2 ? nums[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: LumiVersion, rhs: LumiVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public enum Level: String, Sendable {
        case major, minor, patch
    }

    /// 递增一级，带进位。6.1.9 → minor → 6.2.0；6.9.9 → minor → 7.0.0
    public func bumped(_ level: Level) -> LumiVersion {
        var v = self
        switch level {
        case .major:
            v.major += 1
            v.minor = 0
            v.patch = 0
        case .minor:
            v.patch = 0
            if v.minor < 9 {
                v.minor += 1
            } else {
                v.minor = 0
                v.major += 1
            }
        case .patch:
            if v.patch < 9 {
                v.patch += 1
            } else {
                v.patch = 0
                v = LumiVersion(major: v.major, minor: v.minor, patch: 9).bumped(.minor)
            }
        }
        return v
    }
}

/// 版本号校验结果，对应 CLI 的 `--validate-version`
public enum VersionCheck: Equatable, Sendable {
    case ok
    case fixed(String)
    case invalid

    public var description: String {
        switch self {
        case .ok: return " -> OK"
        case .fixed(let v): return " -> \(v)"
        case .invalid: return " -> (无法解析)"
        }
    }

    /// 校验并给出修正建议：缺段补 0，段值越界（>9）判为非法
    public static func check(_ raw: String) -> VersionCheck {
        guard let v = LumiVersion(raw) else { return .invalid }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".").map(String.init)
        if parts.count == 3, LumiVersion(parts.joined(separator: ".")) == v,
           Int(parts[1])! <= 9, Int(parts[2])! <= 9 {
            return .ok
        }
        return .fixed(v.description)
    }
}
