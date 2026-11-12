#!/bin/bash
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd)"
runtime="$(dirname "$here")/.yecatz-chat"
python="$runtime/venv/bin/python"
iterations="${YECATZ_TRAIN_STEPS:-40}"

if [[ ! -x "$python" || ! -f "$runtime/model-qwen3-4b/.yecatz-ready" ]]; then
    printf '请先运行 setup.command，下载聊天模型。\n' >&2
    exit 1
fi
mkdir -p "$runtime/runs"
run="$(mktemp -d "$runtime/runs/run.XXXXXX")"
export HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
"$python" "$here/prepare_data.py" "$run/data"
"$python" -m mlx_lm lora \
    --config "$here/lora.json" --model "$runtime/model-qwen3-4b" --data "$run/data" --adapter-path "$run/adapter" \
    --train --test --mask-prompt --fine-tune-type lora --num-layers 8 \
    --batch-size 2 --iters "$iterations" --max-seq-length 512 \
    --learning-rate 0.00003 --steps-per-report 10 --steps-per-eval 10 \
    --val-batches -1 --test-batches -1 --save-every 20 --seed 42 2>&1 | tee "$run/train.log"
[[ -s "$run/adapter/adapters.safetensors" && -s "$run/adapter/adapter_config.json" ]]
printf 'runs/%s/adapter\n' "$(basename "$run")" > "$run/active-qwen3-4b-adapter"
mv "$run/active-qwen3-4b-adapter" "$runtime/active-qwen3-4b-adapter"
printf '\n训练完成。重新打开聊天 DLC 即可使用。权重在 %s\n' "$run/adapter"
