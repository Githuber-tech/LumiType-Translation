import Foundation

/// 中/英双语词表。
///
/// 键名与文案逐条取自 `LumiType.exe` 的用户字符串堆（#US heap），
/// 保证 Mac 版界面文案与原版逐字一致 —— 这是「1:1 还原」里最容易被忽略、
/// 也最容易被用户一眼看出来的部分。
public final class I18n {

    public static let shared = I18n()

    /// key → (中文, English)
    public typealias Pair = (zh: String, en: String)

    public let table: [String: Pair]

    public init() {
        table = [
            // 托盘
            "tray_open": ("打开浮层 (&O)", "Open overlay (&O)"),
            "tray_clip": ("剪贴板翻译 (&C)", "Translate clipboard (&C)"),
            "tray_prefs": ("首选项 (&P)…", "Preferences (&P)…"),
            "tray_check": ("检查更新 (&U)", "Check for updates (&U)"),
            "tray_restart": ("重启应用 (&R)", "Restart app (&R)"),
            "tray_about": ("关于 (&A)", "About (&A)"),
            "tray_exit": ("退出 (&X)", "Exit (&X)"),
            "tray_tip": ("LumiType 灵译 {0}", "LumiType {0}"),
            "tray_autostart": ("开机启动", "Start with Windows"),

            // 首选项
            "prefs_title": ("LumiType 灵译 首选项", "LumiType Preferences"),
            "dlg_prefs": ("首选项", "Preferences"),
            "tab_general": ("常规", "General"),
            "tab_log": ("更新日志", "Changelog"),
            "tab_tips": ("使用技巧", "Tips"),
            "tab_feedback": ("用户反馈", "Feedback"),
            "state": ("当前版本 {0}　权限：{1}　开机启动：{2}",
                      "version {0}　privileges: {1}　start with Windows: {2}"),
            "state_normal": ("普通", "normal"),
            "state_admin": ("管理员", "admin"),
            "state_on": ("开", "on"),
            // macOS 版补充：原版「权限：普通/管理员」在 Mac 上对应「辅助功能」授权，
            // 它才是决定译文能否自动插入别的应用的那一项权限。
            "perm_ax_on": ("已授权", "granted"),
            "perm_ax_off": ("未授权", "not granted"),
            "admin_note_mac": (
                "macOS 不区分管理员权限：跨应用插入译文需要「系统设置 → 隐私与安全性 → 辅助功能」里勾选 LumiType；未授权时译文只会进剪贴板。",
                "macOS has no administrator split: inserting into other apps needs LumiType ticked under System Settings > Privacy & Security > Accessibility. Without it the translation only lands on the clipboard."
            ),
            "state_off": ("关", "off"),
            "autostart": ("开机启动", "Start with Windows"),
            "admin": ("以管理员身份运行", "Run as administrator"),
            "admin_note": (
                "提权后可对以管理员权限运行的窗口保持钩子与译文插入能力；切换会重启应用并弹出 UAC 确认。",
                "Elevation keeps hooks and insertion working for windows running as administrator; switching restarts the app and asks for UAC."
            ),

            // 快捷键
            "hotkey_group": ("快捷键（点击输入框，然后按下新组合键）",
                             "Hotkeys (click the box, then press the new combo)"),
            "hk_toggle": ("唤出 / 激活浮层", "Toggle / activate overlay"),
            "hk_clipboard": ("翻译剪贴板", "Translate clipboard"),
            "hk_h1": ("至少含 Ctrl/Alt/Shift/Win 之一", "Must include Ctrl/Alt/Shift/Win"),
            "hk_h2": ("Esc 取消本次修改", "Esc cancels the change"),
            "hk_reset": ("恢复默认快捷键", "Restore default hotkeys"),
            "hk_capture": ("按下新快捷键…", "Press new hotkey…"),
            "hk_err_mod": ("快捷键需至少包含 Ctrl / Alt / Shift / Win 之一",
                           "The hotkey must include at least one of Ctrl / Alt / Shift / Win"),
            "hk_err_key": ("该键不可用作全局快捷键", "This key cannot be used as a global hotkey"),
            "hk_err_busy": ("注册失败：组合键可能已被其它程序占用",
                            "Registration failed: the combo may be in use by another app"),

            // 玻璃 / 皮肤
            "glass_group": ("浮层磨砂玻璃", "Overlay frosted glass"),
            "glass_opacity": ("透明度", "Opacity"),
            "glass_help": ("数值越低背景越透（15-100%）；拖动滑条或直接改百分比，立即作用于所有浮层。",
                           "Lower means more transparent (15-100%). The change applies to every overlay immediately."),
            "skin_group": ("浮层皮肤", "Overlay skin"),
            "skin_light": ("浅色（白色磨砂玻璃）", "Light (white frosted glass)"),
            "skin_dark": ("暗色（夜晚磨砂玻璃）", "Dark (night frosted glass)"),
            "skin_accent": ("主题色（跟随系统主题色）", "Accent (follows system theme)"),
            "skin_help": ("主题色实时读取 Windows 任务栏/系统主题色（DWM 颜色化色）。",
                          "Accent reads the live system accent colour (DWM colorization)."),

            // 引擎
            "engine_group": ("翻译引擎 · API", "Translation engine · API"),
            "eng_google": ("Google 翻译", "Google Translate"),
            "eng_llm": ("LLM（DeepSeek 等）", "LLM (DeepSeek etc.)"),
            "api_apply": ("应用", "Apply"),
            "api_help": ("Key 只保存在本机 config\\settings.json；三种模型可各存一份，同时只用其中一种。",
                         "The key stays on this machine in config\\settings.json; each engine keeps its own and only one is used at a time."),
            "api_yes": ("已配置", "set"),
            "api_no": ("未配置", "none"),
            "api_active": ("当前生效", "active"),
            "api_nokey": ("请先粘贴该模型的 API Key，再点「应用」",
                          "Paste the API key of this model first, then press Apply"),

            // 界面语言 / 配置
            "uilang_group": ("界面语言 · Language", "Interface language"),
            "uilang_label": ("显示语言", "Display language"),
            "uilang_help": ("切换后立即作用于浮层、托盘菜单与本窗口，无需重启。",
                            "Applies to the overlay, tray menu and this window right away; no restart needed."),
            "cfg_group": ("配置", "Settings"),
            "cfg_open": ("打开配置目录", "Open config folder"),
            "cfg_reload": ("重新加载配置", "Reload config"),

            // 浮层状态
            "st_typing": ("输入中", "typing"),
            "st_updating": ("更新中", "updating"),
            "st_translating": ("翻译中", "translating"),
            "st_output": ("输出中", "outputting"),
            "st_done": ("{0}ms · {1} 字", "{0}ms · {1} chars"),
            "st_fail": ("失败", "failed"),
            "st_cache": ("缓存 · {0} 字", "cached · {0} chars"),
            "st_final": ("精译中…", "finalising…"),
            "st_final_fail": ("精译失败，已保留原文", "final failed - kept the source"),
            "st_engine_only": ("只有一个引擎配置了 API Key", "only one engine has an API key"),
            "st_engine_now": ("引擎：{0}", "engine: {0}"),

            // 提示行
            "hints_free": ("点输入框打中文    Enter 输出译文    Ctrl+Enter 输出原文    Esc 关闭浮层",
                           "Click the box and type    Enter sends translation    Ctrl+Enter sends original    Esc closes"),
            "hints_pinned": ("Enter 插入译文到吸附窗口    Ctrl+Enter 插入原文    点右上 ✕ 解除吸附",
                             "Enter inserts the translation    Ctrl+Enter inserts the original    ✕ unpins"),
            "hints_model": ("Enter 输出译文    Ctrl+Enter 输出原文    Tab 切换引擎    Esc 关闭浮层",
                            "Enter sends translation    Ctrl+Enter sends original    Tab switches engine    Esc closes"),
            "cue": ("点输入框打中文…", "Click the box and type…"),

            // 卡片提示
            "tip_close": ("关闭浮层", "Close overlay"),
            "tip_unsnap": ("解除吸附", "Unsnap"),
            "tip_notepad": ("打开记事本", "Open Notepad"),
            "tip_swap": ("对换输入与目标语言", "Swap input and target language"),
            "snap_release": ("松开吸附到 {0}", "release to snap to {0}"),
            "snap_release_only": ("松开吸附", "Release to snap"),
            "snapped": ("已吸附 · {0}", "snapped · {0}"),
            "warn_fail": ("请求失败", "Request failed"),
            "label_translating": ("正在翻译", "Translating"),
            "msg_running": ("LumiType 已经在运行。", "LumiType is already running."),

            // 语言菜单
            "lang_auto_src": ("自动识别（跟随输入）", "Auto detect (follow the text)"),
            "lang_auto_dir": ("自动方向（跟随识别）", "Auto direction (follow detection)"),

            // 错误
            "e_401": ("API Key 无效或已过期 (401)", "API key invalid or expired (401)"),
            "e_402": ("账户余额不足 (402)", "Insufficient account balance (402)"),
            "e_403": ("访问被拒绝 (403)", "Access denied (403)"),
            "e_456": ("DeepL 配额已用完 (456)", "DeepL quota exhausted (456)"),
            "e_429": ("请求过于频繁 (429)", "Too many requests (429)"),
            "e_400": ("请求被拒绝 (400)", "Request rejected (400)"),
            "e_timeout": ("请求超时", "Request timed out"),
            "e_dns": ("无法解析服务器地址，请检查网络或代理",
                      "Cannot resolve the server address; check network or proxy"),
            "e_conn": ("无法连接服务器，请检查网络或代理",
                       "Cannot reach the server; check network or proxy"),
            "e_nokey_d": ("未配置 DeepL API Key，请在首选项「翻译引擎」中粘贴并应用",
                          "No DeepL API key - paste one in Preferences > Engine and press Apply"),
            "e_nokey_g": ("未配置 Google API Key，请在首选项「翻译引擎」中粘贴并应用",
                          "No Google API key - paste one in Preferences > Engine and press Apply"),
            "e_nokey_l": ("未配置 LLM API Key，请在首选项「翻译引擎」中粘贴并应用",
                          "No LLM API key - paste one in Preferences > Engine and press Apply"),
            "err_empty": ("DeepL 返回空译文", "DeepL returned an empty translation"),
            "err_empty_g": ("Google 返回空译文", "Google returned an empty translation"),
            "err_empty_l": ("LLM 返回空译文", "The LLM returned an empty translation"),

            // 更新
            "upd_item": ("一键更新到 V{0} (&U)", "Update to V{0} (&U)"),
            "upd_title": ("发现新版本 V{0}", "New version V{0}"),
            "upd_body": ("打开托盘菜单可一键更新", "Open the tray menu to update with one click"),
            "upd_nosrc": ("更新源未配置：在 config\\settings.json 设置 UpdateUrl 后启用推送",
                          "No update source configured: set UpdateUrl in config\\settings.json"),
            "upd_latest": ("当前已是最新版本 {0}", "Already the latest version {0}"),
            "upd_fail": ("检查更新失败：{0}", "Update check failed: {0}"),
            "upd_sha": ("更新包 SHA256 校验失败，已中止安装",
                        "SHA256 check failed; update aborted"),
            "upd_err": ("更新失败：{0}", "Update failed: {0}"),
            "upd_installfail": ("更新安装失败：{0}", "Install failed: {0}"),
            "upd_titlebox": ("LumiType 更新", "LumiType update"),
            "admin_restart": ("需要重启应用以{0}运行权限，现在重启？",
                              "Restart is required to {0} privileges. Restart now?"),
            "about_title": ("关于 LumiType", "About LumiType"),
            "about_credit": ("作者：詹姆·兰尼斯特 / 抖音号：Jamie_Lannister",
                             "Author: Jamie Lannister / Douyin: Jamie_Lannister"),

            // 反馈
            // macOS 版：存档位置换成 Application Support，其余行为一致
            "fb_desc_mac": (
                "发送反馈会联网提交并自动本地存档（~/Library/Application Support/LumiType/feedback/，每个反馈一个时间戳文件夹）。",
                "Sending submits online and also archives locally (~/Library/Application Support/LumiType/feedback/, one timestamped folder per submission)."
            ),
            "fb_empty": ("暂无反馈记录", "No feedback archived yet"),
            "fb_desc": ("发送反馈会联网提交并自动本地存档（exe 旁 feedback\\ 目录，每个反馈一个时间戳文件夹）；",
                        "Sending submits online and also archives locally (a feedback folder per submission)."),
            "fb_write": ("写反馈…（可加附件）", "Write feedback… (attachments allowed)"),
            "fb_col_dir": ("反馈目录", "Folder"),
            "fb_col_att": ("附件数", "Files"),
            "fb_col_sum": ("内容摘要", "Summary"),
            "fb_opendir": ("打开反馈目录", "Open feedback folder"),
            "fb_title": ("LumiType 用户反馈", "LumiType feedback"),
            "fb_label": ("反馈内容：", "Feedback:"),
            "fb_att_group": ("附件（图片 / PDF，单个 ≤ 20MB）", "Attachments (image / PDF, ≤ 20MB each)"),
            "fb_col_name": ("文件名", "File"),
            "fb_col_size": ("大小", "Size"),
            "fb_add": ("添加附件…", "Add attachment…"),
            "fb_del": ("移除选中", "Remove selected"),
            "fb_send": ("发送反馈", "Send feedback"),
            "fb_cancel": ("取消", "Cancel"),
            "fb_err_empty": ("请填写反馈内容或添加附件。", "Please write feedback or add an attachment."),
            "fb_send_ok": ("反馈已发送（并已在本地存档），感谢！",
                           "Feedback sent (and archived locally). Thank you!"),
            "fb_send_ok2": ("反馈已发送，感谢！", "Feedback sent. Thank you!"),
            "fb_send_fail2": ("发送失败：{0}。内容已本地存档，可稍后重试：",
                              "Send failed: {0}. Archived locally, you can retry later:"),
            "fb_send_fail3": ("发送未成功：{0}", "Send not accepted: {0}"),
            "fb_err_type": ("不支持的附件类型：{0}", "Unsupported attachment type: {0}"),
            "fb_err_big": ("附件超过 20MB：{0}", "Attachment exceeds 20MB: {0}"),
            "fb_err_save": ("保存失败：{0}", "Save failed: {0}"),
            "fb_pick_title": ("选择附件（图片 / PDF）", "Select attachments (image / PDF)"),

            // 使用技巧标题
            "tip1_t": ("① 浮层结构一图看懂", "① The overlay at a glance"),
            "tip2_t": ("② 吸附到聊天软件 / Mailbird（微信 / WhatsApp / TIM / 飞书 / 钉钉 / 记事本）",
                       "② Snap to chat apps / Mailbird (WeChat / WhatsApp / TIM / Feishu / DingTalk / Notepad)"),
            "tip3_t": ("③ 快捷键与 Enter 契约", "③ Hotkeys and the Enter contract"),
            "tip4_t": ("④ 多浮层与焦点", "④ Multiple overlays and focus"),
            "tip5_t": ("⑤ API 申请一：DeepL（官方免费额度，推荐）",
                       "⑤ API guide 1: DeepL (official free tier, recommended)"),
            "tip6_t": ("⑥ API 申请二：Google Cloud Translation（每月 50 万字符免费）",
                       "⑥ API guide 2: Google Cloud Translation (500k characters/month free)"),
            "tip7_t": ("⑦ API 申请三：LLM 接口（DeepSeek 等，按用量计费）",
                       "⑦ API guide 3: an LLM endpoint (DeepSeek etc., pay per use)"),

            // 示意图标注
            "dg_l1": ("徽章行：吸附后出现「已吸附」与 ✕", "Badge row: shows \"snapped\" and ✕ after snap"),
            "dg_l2": ("圆角输入框：点击聚焦出青色光环", "Rounded input: click to focus (cyan glow)"),
            "dg_l3": ("实时译文：流式逐字显示", "Live translation: shown as it arrives"),
            "dg_l4": ("快捷键提示行：随吸附状态切换", "Hint row: switches with snap state"),
            "dg_top_zone": ("上外框 44px 吸附区", "top edge 44px snap zone"),
            "dg_bot_zone": ("下外框 44px 吸附区", "bottom edge 44px snap zone"),
            "dg_drag_snap": ("拖近边线 → 脉冲高亮 + 气泡 → 松手吸附",
                             "drag to edge → pulse highlight → release to snap"),
            "dgk_1": ("唤出 / 激活浮层（每次新建独立实例）",
                      "toggle / activate overlay (a new instance each time)"),
            "dgk_2": ("翻译剪贴板内容", "translate the clipboard content"),
            "dgk_3": ("吸附中 = 译文插入被吸附软件输入框并清空浮层；未吸附 = 输出到原光标处",
                      "snapped = insert into the snapped app and clear; free = output at the caret"),
            "dgk_4": ("输出原文　　Tab 切换已配置引擎　　Esc 关闭浮层（焦点在浮层时）",
                      "output original　　Tab cycles configured engines　　Esc closes (overlay focused)")
        ]
    }

    /// 取指定语言的文案；缺键时原样返回键名（便于在界面上直接发现漏译）
    public func t(_ key: String, _ lang: String) -> String {
        guard let pair = table[key] else { return key }
        return lang == "en" ? pair.en : pair.zh
    }

    /// 取文案并替换 {0} {1} … 占位
    public func t(_ key: String, _ lang: String, _ args: [String]) -> String {
        var text = t(key, lang)
        for (i, a) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(i)}", with: a)
        }
        return text
    }

    /// 所有键，供测试做中英完整性校验
    public var keys: [String] { Array(table.keys).sorted() }
}
