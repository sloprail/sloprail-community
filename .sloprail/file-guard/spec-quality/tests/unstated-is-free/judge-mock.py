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

# Like the real judge on two points. A gap (nothing says what `read X` does to the value) fails
# one_owner only when the prompt does not say that a case no invariant covers is never a finding.
# A boundary built on an undefined word ("the line assigned") fails concrete whatever the prompt.
def decide(path, kind, content):
    if kind != "invariant":
        return {}
    if "the line assigned" in content:
        return {"concrete": "MOCK boundary: whether `$((X=1))` is one the line assigned, readers decide apart"}
    if "Change.kind} is unset" in content and "A gap is never a" not in prompt:
        return {"one_owner": "MOCK gap: no invariant decides what read does to the value"}
    return {}
# Every failing item is material (it blocks): an input inside the boundary, two readings, two outputs.
MATERIAL = {"input": "cd /a", "reading_a": "A", "output_a": "cwd /a", "reading_b": "B", "output_b": "cwd unknown"}
out = {}
for path, kind, content in files:
    fails = decide(path, kind, content)
    out[path] = {"probes": ["mock probe"], "items": {i: ({"ok": False, "evidence": fails[i], "material": MATERIAL} if i in fails else {"ok": True, "evidence": "mock ok"}) for i in items[kind]}}
print(json.dumps({"files": out}))
