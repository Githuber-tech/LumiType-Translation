# LumiType 灵译（Windows-only）

LumiType 是一个 Windows 实时打字翻译浮层：按 `Alt+Y` 唤出，在浮层中输入文字，按 `Enter` 将译文回填到原窗口。

## 下载

- [下载 LumiType.exe](https://raw.githubusercontent.com/Githuber-tech/LumiType-Translation/main/LumiType.exe)
- [查看 Windows Release](https://github.com/Githuber-tech/LumiType-Translation/releases)

当前项目只维护 Windows 版本；macOS 版本、macOS 源码和 macOS 发布包已停止维护并从仓库移除。

## 快速开始

1. 将 `LumiType.exe` 放到任意目录并运行。
2. 首次运行后，在 exe 同级 `config\settings.json` 填入你自己的翻译 API Key。
3. 按 `Alt+Y` 唤出浮层，输入文字，按 `Enter` 输出译文。

## 快捷键

| 快捷键 | 作用 |
|---|---|
| `Alt+Y` | 唤出新的翻译浮层 |
| `Ctrl+Alt+Y` | 翻译剪贴板 |
| `Enter` | 输出译文 |
| `Ctrl+Enter` | 输出原文 |
| `Shift+Enter` | 换行 |
| `Tab` | 切换已配置的翻译引擎 |
| `Esc` | 不关闭浮层；点击卡片 `✕` 关闭 |

## 当前版本

`V0.0.17`

本版本从 macOS 最新功能中移植了适用于 Windows 的功能性改进：只吸附唤出前的前台应用；旧版 `1.x/6.x` 客户端可通过更新桥升级到 `0.0.x`；Enter 回填等待目标窗口真正激活，失败时保留剪贴板并提示手动 `Ctrl+V`；最小化窗口保持停靠，恢复后继续跟随。

## 自动更新

程序读取仓库中的 [`latest.json`](https://raw.githubusercontent.com/Githuber-tech/LumiType-Translation/main/latest.json)，下载 Windows exe 后校验 SHA256。当前清单仅包含 Windows 发布信息。
