# LumiType 灵译 - Real-time typing translation overlay (Windows + macOS)

Type in a floating overlay next to your caret, press **Enter**, and the translation is pasted
back into the chat app you were already in (WeChat, WhatsApp, Feishu, DingTalk, Notepad,
Mailbird, and most windows). No copy-paste, no context switching.

Same version number on both platforms, same config file format, one Release page.

![LumiType in use](preview.png)

## Download

| Platform | File | Notes |
|---|---|---|
| **Windows 10/11** | `LumiType.exe` | Portable single file, no installer, no dependencies |
| **macOS 13+** | `LumiType-<version>-macOS.dmg` | Universal (Apple Silicon + Intel) |
| macOS (auto-update package) | `LumiType-<version>-macOS.zip` | What the built-in updater downloads |

- **Releases:** <https://github.com/Githuber-tech/LumiType-Translation/releases> - every release
  carries all of the files above, so there is no version to hunt for.
- Direct links (always the latest):
  - Windows: <https://raw.githubusercontent.com/Githuber-tech/LumiType-Translation/main/LumiType.exe>
  - macOS: <https://raw.githubusercontent.com/Githuber-tech/LumiType-Translation/main/LumiType-macOS.zip>
- Integrity: [`latest.json`](latest.json) carries the SHA256 of both packages.

## Windows quick start (3 steps)

1. Put `LumiType.exe` anywhere (e.g. `D:\Tools\LumiType\`) and double-click. It lives in the tray.
2. First run creates `config\settings.json` next to the exe - fill in **your own** DeepL API key:

   ```json
   { "ApiKey": "your-key:fx", "UiLang": "zh" }
   ```

   - Get a free key: register at <https://www.deepl.com/developer> → *Your apps* → *Create new app*
     (free tier: 500,000 characters per month).
   - Save the file, then restart the app (or tray → *Reload config*).
3. Press **Alt+Y** to summon an overlay anywhere. Type, then **Enter** sends the translation.

## macOS quick start (4 steps)

1. Open the `.dmg`, drag **LumiType** into `/Applications`, then launch it. It lives in the menu bar.
2. The package is ad-hoc signed and not notarized, so on first launch Gatekeeper may block it:
   right-click the app → **Open**, or run
   `xattr -dr com.apple.quarantine /Applications/LumiType.app`.
3. Grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility) so
   `Enter` can paste the translation back into the app you came from.
4. Press **⌥Y** to summon the overlay, type, then **Enter**. The API key is set in
   *Preferences → General → DeepL / Google / LLM*, or by editing
   `~/Library/Application Support/LumiType/settings.json` - the 44 keys are identical to
   the Windows build, so a Windows config file can be dropped in as-is.

## Hotkeys

| Windows | macOS | Action |
|---|---|---|
| Alt+Y | ⌥Y | Open a new overlay at the pointer (multiple independent ones allowed) |
| Ctrl+Alt+Y | ⌃⌥Y | Translate the clipboard content |
| Enter | Return | Snapped: paste the translation into the snapped app · Free: output at your original caret |
| Ctrl+Enter | ⌘Return | Output the original text |
| Tab | Tab | Switch between the configured engines |
| Shift+Enter | ⇧Return | New line |
| Esc | Esc | Close the active overlay (ignored while snapped) |

10 built-in languages with auto-detect, engine switch (DeepL / Google / LLM), interface language
(zh / en), glass opacity, skin and hotkeys are all in Preferences. The macOS build also snaps to
the windows of 21 apps (WeChat, Feishu, DingTalk, Chrome, VS Code, ...) and exits automatically
when the snapped window closes.

## Auto update

While online, the app checks the version manifest at startup and every 6 hours, and offers a
one-click update from the tray / menu bar (menu → *Check for updates*).
Manifest: [`latest.json`](latest.json). Each platform only ever downloads its own package: the
top-level `url`/`sha256` describe `LumiType.exe`, the `mac` object describes `LumiType-macOS.zip`.
A macOS build will never fetch the `.exe`.

## Privacy

No telemetry, no analytics. The only network calls are the translation API and the optional
update check. Your API key is stored in plain text on your own machine and never leaves it -
each user should use their own key.

---

## 中文说明

LumiType 灵译：把光标旁的浮层当输入框打字，按 **Enter**，译文直接插回你正在用的软件
（微信 / WhatsApp / 飞书 / 钉钉 / 记事本 / Mailbird 等），免复制粘贴、免切换窗口。
两个平台**永远同号**，同一张 Release 页面同时给出两端安装包。

**下载**

| 系统 | 文件 | 说明 |
|---|---|---|
| Windows 10/11 | `LumiType.exe` | 单文件绿色版，无安装、无依赖 |
| macOS 13+ | `LumiType-<版本>-macOS.dmg` | 通用包，Apple Silicon 与 Intel 通用 |
| macOS（自动更新） | `LumiType-<版本>-macOS.zip` | 程序内一键更新时下载的包 |

**Windows 上手三步**
1. 把 `LumiType.exe` 放到任意目录，双击运行；程序常驻托盘；
2. 首跑会在 exe 旁生成 `config\settings.json`，填入**你自己的** DeepL API Key
   （<https://www.deepl.com/developer> 注册 → *Your apps* → *Create new app*，
   免费档每月 50 万字符）；保存后重启或托盘 → 重新加载配置；
3. 按 **Alt+Y** 唤出浮层，打字，**Enter** 输出译文。

**macOS 上手四步**
1. 打开 `.dmg`，把 **LumiType** 拖进 `/Applications`，启动后常驻菜单栏；
2. 安装包为本地 ad-hoc 签名、未公证，首次启动若被拦截：右键 App → **打开**，
   或执行 `xattr -dr com.apple.quarantine /Applications/LumiType.app`；
3. 授予**辅助功能**权限（系统设置 → 隐私与安全性 → 辅助功能），Enter 才能把译文插回原软件；
4. 按 **⌥Y** 唤出浮层，打字，**Enter** 输出。API Key 在「首选项 → 常规 → DeepL / Google / LLM」
   填写，或直接改 `~/Library/Application Support/LumiType/settings.json`
   （44 个字段与 Windows 版同名同义，配置文件可直接互换）。

界面语言（中/英）、翻译语言对、透明度、皮肤、快捷键：托盘或菜单栏 → 首选项。
联网时启动后及每 6 小时自动检查更新，可一键升级；macOS 端只会下载 zip，绝不会去下 exe。
无遥测、无统计；你的 key 不会离开本机。
