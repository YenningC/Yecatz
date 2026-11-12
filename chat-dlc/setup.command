#!/bin/bash
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd)"
runtime="$(dirname "$here")/.yecatz-chat"
python="${PYTHON:-python3}"

if [[ "$(uname -m)" != arm64 ]]; then
    printf '聊天 DLC 需要 Apple 芯片的 Mac。\n' >&2
    exit 1
fi
if [[ ! -x "$runtime/venv/bin/python" ]]; then
    if ! "$python" -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
        printf '请先安装 Python 3.11 或更新版，再运行此文件。也可通过 PYTHON 指定 Python 路径。\n' >&2
        open https://www.python.org/downloads/macos/ || true
        exit 1
    fi
    "$python" -m venv "$runtime/venv"
fi
export PIP_DISABLE_PIP_VERSION_CHECK=1
"$runtime/venv/bin/python" -m pip install --no-cache-dir -r "$here/requirements.txt"
"$runtime/venv/bin/python" "$here/download.py" "$runtime"
printf '\n配置完成。可以打开「Yecatz Chat.app」。\n'
