"""The optional chat app speaks newline-delimited JSON to this local process."""

import json
import os
import sys
from pathlib import Path

output = sys.stdout
sys.stdout = sys.stderr
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"


def emit(event, **fields):
    print(json.dumps({"event": event, **fields}, ensure_ascii=False), file=output, flush=True)


def adapter_for(root):
    marker = root / "active-qwen3-4b-adapter"
    if marker.is_file():
        path = (root / marker.read_text(encoding="utf-8").strip()).resolve()
        if not path.is_relative_to((root / "runs").resolve()):
            raise ValueError("人设权重的位置不正确。")
    else:
        path = root / "adapter-qwen3-4b"
        if not path.exists():
            return None
    for name in ("adapter_config.json", "adapters.safetensors"):
        if not (path / name).is_file():
            raise ValueError("人设权重不完整，请重新训练或安装。")
    return path


def main():
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler

    root = Path(sys.argv[1]).resolve()
    persona = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
    adapter = adapter_for(root)
    model, tokenizer = load(root / "model-qwen3-4b", adapter_path=adapter)
    sampler = make_sampler(temp=0.7, top_p=0.8, top_k=20)
    emit("ready", trained=adapter is not None)

    for line in sys.stdin:
        try:
            messages = json.loads(line)["messages"][-13:]
            if not messages or messages[-1]["role"] != "user":
                raise ValueError("需要一条用户消息。")
            prompt = tokenizer.apply_chat_template(
                [{"role": "system", "content": persona}, *messages],
                tokenize=True,
                return_dict=False,
                add_generation_prompt=True,
            )
            wrote = False
            for chunk in stream_generate(model, tokenizer, prompt, max_tokens=192, sampler=sampler):
                if chunk.text:
                    emit("text", text=chunk.text)
                    wrote |= bool(chunk.text.strip())
            emit("done" if wrote else "error", text=None if wrote else "Yecatz 没有回话，再试一次。")
        except BrokenPipeError:
            return
        except Exception as error:
            print(error, file=sys.stderr)
            emit("error", text="这条消息没有处理完，请重试。")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
    except Exception as error:
        print(error, file=sys.stderr)
        emit("error", text="加载聊天模型失败。请重新配置，或检查人设权重。")
        sys.exit(1)
