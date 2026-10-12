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

# Like the real judge on one point of document-invariant: "valid shell syntax" with no named
# grammar is open-ended; it fails `concrete` only when the skill rule is in the prompt.
def decide(path, kind, content):
    if kind == "invariant" and "valid shell syntax" in content and "### An invariant is concrete" in prompt:
        return {"concrete": "MOCK not concrete"}
    return {}
out = {}
for path, kind, content in files:
    fails = decide(path, kind, content)
    out[path] = {"items": {i: {"ok": i not in fails, "evidence": fails.get(i, "mock ok")} for i in items[kind]}}
    if os.environ.get("DROP_ITEM") and path.endswith(os.environ["DROP_ITEM"]):
        out[path]["items"].pop(items[kind][-1])
if os.environ.get("OMIT"):
    out.pop(files[-1][0])
print(json.dumps({"files": out}))
