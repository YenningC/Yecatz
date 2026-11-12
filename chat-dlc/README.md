# Yecatz Chat DLC（已停用）

聊天已经集成到 `Yecatz.app`，通过 API 工作，不再需要本地模型、Python 环境或独立的聊天 App。

这个目录只保留早期本地 Qwen3 LoRA 的实验记录：

- `worker.py`、`download.py`、`setup.command`、`train.command` 和 `requirements.txt` 是旧的本地推理/训练脚本；
- `data/` 和 `persona.txt` 是当时的训练数据与角色设定，主程序现在使用项目根目录的 `persona.txt`；
- `.yecatz-chat/` 是旧运行时和训练结果，可以整个删除。

当前的构建、聊天配置和 API 说明见项目根目录的 [README](../README.md)。
