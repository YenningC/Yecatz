"""Download the exact base checkpoint shared by training and inference."""

import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
os.environ["HF_HOME"] = str(root / "hf")
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"

from huggingface_hub import snapshot_download

MODEL = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
REVISION = "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"

snapshot_download(
    MODEL,
    revision=REVISION,
    local_dir=root / "model-qwen3-4b",
    token=False,
    allow_patterns=["*.json", "chat_template.jinja", "merges.txt", "model.safetensors"],
)
(root / "model-qwen3-4b" / ".yecatz-ready").write_text(REVISION + "\n", encoding="utf-8")
