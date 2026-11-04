import Foundation

/// 提示词与语言方向推断。
///
/// 说明：原版 `Prompt` 类只有一个字段 `BuiltInTargets`，
/// 具体文案是在方法里拼接的，二进制里只保留了片段
/// （`Translation:`、` Context: `）。下面的措辞为复刻其语义的重建版本，
/// 不影响行为，只影响 LLM 引擎的输出风格。
public enum Prompt {

    /// 内置目标语言，顺序与 `Languages.all` 一致
    public static let builtInTargets: [String] = Languages.all.map(\.code)

    /// 送给 LLM 的系统级指令
    public static func translationInstruction(target: String, source: String = "auto") -> String {
        let from = source == "auto" ? "" : " from \(Languages.find(source)?.nameEn ?? source)"
        return """
        You are a translation engine. Translate the user text\(from) into \(target).
        Rules:
        - Output only the translation, no explanations, no quotes, no markdown.
        - Preserve the original line breaks, punctuation style and tone.
        - Keep proper nouns, code, URLs and emoji unchanged.
        - If the text is already in \(target), return it unchanged.
        """
    }

    /// 精译模式（QualityModel）追加的质量约束。
    /// 原版 V5.9.0「整段精译：取消片段追加，补齐 DeepL 质量参数」即此路径。
    public static func qualityAddendum() -> String {
        "Translate the whole passage as one unit; do not translate sentence by sentence in isolation."
    }

    /// 是否包含汉字 —— 原版 `HasHan`，用于自动判断输入语言方向
    public static func hasHan(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// 是否 CJK 字符（含扩展 A、兼容区、假名、韩文）
    public static func isCjk(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF,
             0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    /// 自动方向：输入含汉字 → 译为英文；否则译为中文。
    /// 原版 `AutoDirection` 的行为（浮层上「自动方向（跟随识别）」）。
    public static func autoPair(for text: String, uiLang: String) -> (source: String, target: String) {
        hasHan(text) ? ("zh-CN", "en") : ("en", "zh-CN")
    }
}
