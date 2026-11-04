import Foundation

/// 语言方向解析 —— 逐行对照 `src/Engine.cs` 的 `Prompt` 静态方法移植。
///
/// 这一层是 Windows 版的「自动方向」核心：卡片上的两个语言胶囊、
/// 实际发出的 `source_lang` / `target_lang` 都由它决定。
/// 原版全部在本地完成，不产生任何网络请求，这里保持一致。
public enum LanguageResolver {

    // MARK: - 脚本识别

    /// 对应 `Prompt.DetectClass`：按字符区段统计出主脚本类。
    /// 顺序很重要 —— 只要出现一个汉字就判为中文（混排输入以中文为主）。
    public static func detectClass(_ text: String) -> String {
        if text.isEmpty { return "en" }
        var han = 0, kana = 0, hangul = 0, cyr = 0, latin = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            switch v {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF: hangul += 1
            case 0x0400...0x04FF: cyr += 1
            default:
                if (v >= 65 && v <= 90) || (v >= 97 && v <= 122) { latin += 1 }
            }
        }
        if han > 0 { return "zh" }
        if kana > 0 { return "ja" }
        if hangul > 0 { return "ko" }
        if cyr > 0 { return "ru" }
        if latin > 0 { return "en" }
        return "en"
    }

    /// 对应 `Prompt.NameOfClass`：脚本类 → 显示名（也是写进配置的语言名）
    public static func nameOfClass(_ cls: String) -> String {
        switch cls {
        case "zh": return "简体中文"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "ru": return "Русский"
        default: return "English"
        }
    }

    /// 显示名 → 脚本类（`Prompt.ClassOf`）
    public static func classOf(_ langName: String) -> String {
        switch langName {
        case "简体中文", "繁體中文", "zh-CN", "zh-TW": return "zh"
        case "English", "en": return "en"
        case "日本語", "ja": return "ja"
        case "한국어", "ko": return "ko"
        case "Français", "fr": return "fr"
        case "Deutsch", "de": return "de"
        case "Español", "es": return "es"
        case "Português", "pt": return "pt"
        case "Русский", "ru": return "ru"
        default: return langName
        }
    }

    // MARK: - 卡片上的输入侧语言

    /// 输入侧胶囊文案：有输入时跟随实时脚本，无输入时用配置的输入语言。
    public static func resolveSource(_ cfg: Config, text: String) -> String {
        if cfg.pinSource, !cfg.sourceLang.isEmpty { return displayName(cfg.sourceLang) }
        if !text.isEmpty { return nameOfClass(detectClass(text)) }
        return cfg.sourceLang.isEmpty ? "简体中文" : displayName(cfg.sourceLang)
    }

    /// 把配置里可能存的代码（zh-CN / en）转成显示名
    public static func displayName(_ raw: String) -> String {
        if let lang = Languages.find(raw) { return lang.nameZh }
        return raw
    }

    // MARK: - 目标语言

    /// 输出语言：配置的目标语言；若输入已经是该语言，则翻回配置的输入侧
    /// （原版 V4.5.0 起「自动方向」常开，`PinTarget` 可显式锁定）。
    public static func resolveTarget(_ cfg: Config, text: String) -> String {
        let target = cfg.targetLang.isEmpty ? "English" : displayName(cfg.targetLang)
        if cfg.pinTarget { return target }
        if !text.isEmpty, classOf(target) == detectClass(text) {
            let src = cfg.sourceLang.isEmpty ? "简体中文" : displayName(cfg.sourceLang)
            if classOf(src) != classOf(target) { return src }
        }
        return target
    }

    // MARK: - 发给引擎的代码

    /// DeepL `source_lang`：只对 CJK / 俄文给值，拉丁语系交给服务端识别。
    /// 对应 `Prompt.DeepLSourceCode(cfg, text)`。
    public static func deepLSource(_ cfg: Config, text: String) -> String {
        let cls: String
        if cfg.pinSource, !cfg.sourceLang.isEmpty {
            cls = classOf(cfg.sourceLang)
        } else {
            cls = detectClass(text)
        }
        switch cls {
        case "zh": return "ZH"
        case "ja": return "JA"
        case "ko": return "KO"
        case "ru": return "RU"
        default: return ""
        }
    }

    /// Google `source`：同样只在能确定脚本时给值。
    public static func googleSource(_ cfg: Config, text: String) -> String {
        let cls: String
        if cfg.pinSource, !cfg.sourceLang.isEmpty {
            cls = classOf(cfg.sourceLang)
        } else {
            cls = detectClass(text)
            if cls == "en" { return "" }   // 拉丁语系共用一套字母，交给 Google 判断
        }
        switch cls {
        case "zh": return "zh-CN"
        case "ja": return "ja"
        case "ko": return "ko"
        case "ru": return "ru"
        default: return ""
        }
    }

    /// DeepL 的 `context` 字段（不计费）。原版用来稳定商务口吻。
    public static func contextFor(target: String) -> String {
        if classOf(target) == "en" {
            return "A live business chat message being written by a Chinese supplier to an overseas buyer. "
                + "Translate into natural, concise, business-casual English that a native speaker would "
                + "actually type in a chat window. Keep the meaning exact and the original tone; never add "
                + "connectives, subjects or information that the source does not contain."
        }
        return "A live business chat message between two companies. Translate naturally, concisely and "
            + "idiomatically, keeping the original tone; never add information that the source does not contain."
    }

    /// 引擎胶囊文案（`Prompt.EngineLabel`）
    public static func engineLabel(_ cfg: Config) -> String {
        Provider(rawValue: cfg.provider)?.shortLabel ?? "DeepL"
    }
}

/// 产品版本。
///
/// 注意区分两个「版本」：
/// - **macOS 版自身版本 = 2.0.0**（本文件，写进 Info.plist / 托盘 / 更新比较）
/// - **功能基线 = Windows 版 V6.2.0**（`src/` 源码，行为对齐的目标）
/// 两者不是一回事，更新日志里 macOS 的 2.0.0 条目排在最前，后面接继承的 Windows 历史。
public enum Product {
    public static let version = LumiVersion(major: 2, minor: 0, patch: 0)
    public static let versionText = "2.0.0"
    /// 行为对齐的 Windows 基线版本（只用于文档与日志，不参与版本比较）
    public static let parityBaseline = "6.2.0"
    public static let bundleIdentifier = "com.lumitype.mac"
    public static let displayName = "LumiType"
    public static let repositoryURL = "https://github.com/Githuber-tech/LumiType-Translation"
}
