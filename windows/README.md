# Yecatz for Windows

这是 Windows 移植中的开发版本，尚未在 Windows 上完成实机验证。它使用独立的 Qt 窗口实现桌宠，而非运行 macOS 应用。

目前已实现透明悬浮窗口、入场、眨眼、点击互动、衣橱换装、镶钻面罩闪光、回收站拖放、文件阅读、API 聊天及快捷回复、天气查询、本地音乐或在线试听、局域网传文件、托盘菜单、每小时短句和 GitHub 更新检查。动画及功能与 macOS 版本仍有差异，例如聊天暂不保存长期记忆，音乐控制和天气指令的覆盖范围也较少。

## 在 Windows 上构建

需要 64 位 Windows 和 Python 3.12。构建前请向维护者取得完整的 `Assets` 素材。构建脚本会在安装依赖之前检查 `AppIcon.icns`、`cat.png`、`cat-blink.png`、`cat-entry.png`、`pixel-zh-hans.ttf` 和 `tie-status.png`，并列出缺少或为空的文件。

打开 PowerShell，在项目根目录运行下面的命令。

```powershell
.\windows\build.ps1
```

构建完成后，`dist\Yecatz-Windows-x64.zip` 包含运行所需的文件。解压整个文件夹并运行 `Yecatz.exe`。

发布时通过参数指定版本，并创建同名的正式 GitHub Release。下面的 `1.0.0_W` 用于演示格式，实际发布时请使用高于已有 Windows Release 的版本号。

```powershell
.\windows\build.ps1 -Version 1.0.0_W
```

将构建产物 `dist\Yecatz-Windows-x64.zip` 上传至 `1.0.0_W` Release。构建脚本会生成 `Yecatz/update-version.json`，应用通过该文件识别已安装版本。请完整保留压缩包内容，并在 Windows 上实测通过后发布。

## 更新

启动时会后台检查更新，也可以从托盘菜单选择「检查更新…」。Windows 只接受 `_W` 标签的正式版本，并下载 `Yecatz-Windows-x64.zip`。确认更新后，程序会下载、验证并替换当前安装，重新启动成功后自动清理本次替换产生的旧版备份。安装或启动失败时会尝试恢复旧版。

更新只替换 `Yecatz.exe`、`_internal` 和 `update-version.json`，保留安装目录里的其他文件。如果更新中断，关闭所有 Yecatz 窗口和托盘进程，再运行安装目录旁的恢复脚本。例如安装在 `Yecatz` 文件夹时，运行旁边 `.Yecatz.yecatz-update` 文件夹里的 `Restore-Yecatz.cmd`。若安装尚未确认成功，脚本会恢复旧版。若新版已确认启动，脚本会完成备份清理。

请先结束文件传输，并将应用放在当前账号可写入的目录。旧版用户需要先手动安装一次包含此更新功能的版本。两端的发布规则见项目根目录的 README。

## 更新回归测试

在 Windows 上从源码根目录运行以下命令。安装事务测试使用临时测试应用，需要系统 Windows PowerShell 和 .NET Framework 的 C# 编译器。

```powershell
py -3.12 -m unittest discover -s windows -p "test_update*.py" -v
```

## 使用

右键 Yecatz 或点击托盘图标打开菜单。选择「聊天设置…」填写 HTTPS API 地址、模型和密钥；密钥保存在系统凭据管理器。

当聊天地址为 OpenRouter、模型支持工具调用时，Yecatz 可以按需搜索和读取公开网页；其他服务暂不支持此功能。联网工具可能产生额外费用，即使模型本身免费。默认不主动列出来源，问它来源时可以请求提供。

聊天选择「和 Yecatz 聊天」，输入「今天天气怎么样」可查询天气，首次输入城市名称。音乐文件可放进用户目录的 `Music\Yecatz` 文件夹；没有本地音乐时会尝试播放试听。普通模式下，把文件拖到 Yecatz 身上会移入 Windows 回收站。

将鼠标悬停在 Yecatz 身上，点击聊天按钮旁的眼镜按钮开启阅读模式，再拖入一个 UTF-8 文本文件进行总结；再次点击关闭。阅读模式下文件不会进入回收站。文件上限为 5 MB，超过 2 万字只总结前 2 万字；Windows 版暂不支持 PDF、Word 和图片。总结需要已配置的聊天 API，文件文字会发送给该服务商。

Qt、字体和其他依赖的许可证请在正式分发前一并核对。

## 同网传文件

选择托盘菜单「生成连接码…」并把八位数字连接码私下发给对方；另一台设备选择「输入连接码…」。确认连接后，把单个文件拖到 Yecatz 抱着的纸箱上。接收方选择保存位置后开始传输。单个文件最大 1 GB，已有文件不会覆盖。断开连接后恢复普通点击和回收站拖放。八位短码可能被局域网中的旁观者离线猜出，不适合传输敏感文件。

Mac 与 Windows 的新版采用相同的连接码和加密协议。设备发现使用 UDP 广播端口 47857；校园网如果开启设备隔离或禁止广播，连接可能超时。当前不支持跨网络中转。Windows 版仍需在 Windows 实机完成构建和测试。
