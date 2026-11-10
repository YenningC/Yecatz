# Yecatz
A well-dressed pixel cat for your desktop. Stay stressed, dress well.

Yecatz 是一只穿西装的像素橘猫桌宠。他会在桌面上陪你聊天、推荐音乐、查询天气，也会偶尔说一句简短的话。

<img src="Assets/cat.png" alt="穿西装、打领带的像素橘猫 Yecatz" width="220">

## 下载与运行

前往项目的 **Releases** 页面，下载 `Yecatz-macOS-arm64.zip`，解压后打开 `Yecatz.app`。

当前版本支持 **Apple 芯片的 Mac，系统要求 macOS 14 或更新版本**。Windows 版本尚未完成。

应用目前未经过 Apple 公证。如果首次打开时被 macOS 阻止，请在确认下载来源可信后，前往「系统设置 → 隐私与安全性」，选择「仍要打开」。

## 和 Yecatz 相处

- **单击**：随机挥手、送花或流泪，偶尔还会触发隐藏动作。按住 Option 单击可直接触发隐藏动作。
- **双击**：收到粉色爱心和泡泡。
- **拖动**：把 Yecatz 放到桌面上喜欢的位置。
- **拖放文件**：把文件拖到 Yecatz 身上，他会播放处理文件的动画，并将文件移入 macOS 废纸篓。
- **聊天**：鼠标悬浮在 Yecatz 身上，点击出现的「…」按钮，或者右键点击他。
- **每小时一句**：Yecatz 会在空闲时说一句短句。可以通过菜单栏的领带图标关闭。

## 聊天设置

闲聊使用 OpenAI 兼容的 API。第一次使用时，打开菜单栏领带图标中的「聊天设置…」，填写 API 地址、模型和密钥。

例如，可以使用 OpenRouter 的免费模型：

| 设置项 | 值 |
| --- | --- |
| API 地址 | `https://openrouter.ai/api/v1` |
| 模型 | `openrouter/free` |
| API 密钥 | 自己的 OpenRouter 密钥 |

API 的可用性、额度和费用由所选服务商决定。本地 OpenAI 兼容接口也可以使用，密钥可留空。天气、音乐等内置指令无需聊天 API。

## 可以试试说

- 「今天天气怎么样」——首次会问你所在的城市；也可以说「上海今天天气怎么样」或「天气城市设为广州」。天气数据来自 [Open-Meteo](https://open-meteo.com/)。
- 「给我放一首你喜欢的音乐」——Yecatz 会从自己的歌单里挑一首，有匹配的本地文件时播放整首，否则尝试试听或音乐资料库。
- 「放点音乐」「暂停」「下一首」「大声点」。
- 「几点了」「今天几号」「打开浏览器」「打开计算器」。

菜单栏的「打开音乐文件夹」会打开 `~/Music/Yecatz`。把无 DRM 的音乐文件放进去后，Yecatz 可以直接播放。控制 Music 或 Spotify 时，macOS 可能会询问自动化权限。

## 记忆与隐私

Yecatz 不保存完整聊天记录，但会在 `memory.md` 中记录聊天中值得记住的信息。记忆文件通常位于应用旁边，也可能位于 `~/Library/Application Support/Yecatz/memory.md`。可以从菜单栏打开、编辑或删除它。

使用远程聊天 API 时，人设、相关记忆、最近几轮上下文和当前消息会发送给所选服务商。每次回复后，应用还会调用一次 API 更新记忆，消耗对应服务的额度。

密钥优先保存在 macOS 钥匙串；如果钥匙串不可用，应用会提示并将密钥保存在仅当前用户可读的本地文件中。不要将自己的 API 密钥或 `memory.md` 上传到公开仓库。

## 从源码构建

需要 macOS 14 或更新版本，以及 Xcode 或 Command Line Tools。

```bash
./build.sh
open Yecatz.app
```

如果需要手动指定 SDK：

```bash
SDKROOT=/path/to/MacOSX.sdk ./build.sh
```

角色设定保存在 [persona.txt](persona.txt)，修改后重新构建即可生效。

## 素材与致谢

- 像素字体使用 [缝合像素字体 / Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font)。字体许可证随项目保存在 `Assets/Font-Licenses/`。
- 天气数据由 [Open-Meteo](https://open-meteo.com/) 提供。
