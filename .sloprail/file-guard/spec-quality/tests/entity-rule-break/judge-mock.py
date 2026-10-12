#!/usr/bin/env python3
# Mock judge for spec-quality: keeps its prompt (PROMPT_LOG) and answers the checklist, read off
# the prompt, for every file under "The files to judge", each item ok unless decide() fails it.
import json, os, re, sys
prompt = "".join(l for l in sys.stdin if not l.startswith('{"event":'))
open(os.environ["PROMPT_LOG"], "a").write(prompt)
check = prompt.split("## The checklist", 1)[1].split("## Rules for invariants", 1)[0]
inv_part, ent_part = check.split("\nEntity:", 1)
items = {"invariant": re.findall(r"(?m)^- `(\w+)`", inv_part), "entity": re.findall(r"(?m)^- `(\w+)`", ent_part)}
judged = prompt.split("## The files to judge", 1)[1].split("## Entities they cite", 1)[0]
files = re.findall(r'(?s)<file path="([^"]+)" kind="(\w+)">\n(.*?)\n</file>', judged)

# Like the real judge on entity_rules: a bound on one field's own value written in an invariant
# belongs on the field; only when the document-entity rules are in the prompt.
def decide(path, kind, content):
    if kind == "invariant" and "at most 64 bytes long" in content and "<entity_rules>" in prompt \
            and "### A value constraint lives in constraint_expr or enum, not prose" in prompt:
        return {"entity_rules": "MOCK entity rule: the bound on {@fld:v:Variable.name} belongs in its constraint_expr"}
    return {}
# Every failing item is material (it blocks): an input inside the boundary, two readings, two outputs.
MATERIAL = {"input": "cd /a", "reading_a": "A", "output_a": "cwd /a", "reading_b": "B", "output_b": "cwd unknown"}
out = {}
for path, kind, content in files:
    fails = decide(path, kind, content)
    out[path] = {"probes": ["mock probe"], "items": {i: ({"ok": False, "evidence": fails[i], "material": MATERIAL} if i in fails else {"ok": True, "evidence": "mock ok"}) for i in items[kind]}}
    if os.environ.get("DROP_ITEM") and path.endswith(os.environ["DROP_ITEM"]):
        out[path]["items"].pop(items[kind][-1])
if os.environ.get("OMIT"):
    out.pop(files[-1][0])
print(json.dumps({"files": out}))
