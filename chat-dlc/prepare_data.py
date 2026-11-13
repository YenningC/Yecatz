"""Add the shared persona to each example, leaving the original JSONL editable."""

import json
import sys
from pathlib import Path

source = Path(__file__).resolve().parent
output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
persona_file = (source / "persona.md") if (source / "persona.md").exists() else (source / "persona.txt")
persona = persona_file.read_text(encoding="utf-8").strip()
prompts = set()

for split in ("train", "valid", "test"):
    examples = []
    for line in (source / "data" / f"{split}.jsonl").read_text(encoding="utf-8").splitlines():
        messages = json.loads(line)["messages"]
        roles = [item["role"] for item in messages]
        assert roles and len(roles) % 2 == 0
        assert roles == ["user", "assistant"] * (len(roles) // 2)
        assert all(item["content"].strip() for item in messages)
        prompt = messages[-2]["content"]
        if prompt in prompts:
            raise ValueError(f"重复的最后一条用户消息：{prompt}")
        prompts.add(prompt)
        examples.append({"messages": [{"role": "system", "content": persona}, *messages]})
    if not examples:
        raise ValueError(f"{split} 为空")
    (output / f"{split}.jsonl").write_text(
        "".join(json.dumps(example, ensure_ascii=False) + "\n" for example in examples),
        encoding="utf-8",
    )
    print(f"{split}: {len(examples)}")
