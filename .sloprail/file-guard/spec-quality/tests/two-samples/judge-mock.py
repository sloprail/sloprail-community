#!/usr/bin/env python3
# Mock judge for spec-quality: keeps its prompt (PROMPT_LOG), counts its calls per file (CALLS, a
# folder), and answers the checklist for every file under "The files to judge", each item ok
# unless decide() fails it, with or without a `material` finding.
import json, os, re, sys
prompt = "".join(l for l in sys.stdin if not l.startswith('{"event":'))
open(os.environ["PROMPT_LOG"], "a").write(prompt)
check = prompt.split("## The checklist", 1)[1].split("## Rules for invariants", 1)[0]
inv_part, ent_part = check.split("\nEntity:", 1)
items = {"invariant": re.findall(r"(?m)^- `(\w+)`", inv_part), "entity": re.findall(r"(?m)^- `(\w+)`", ent_part)}
judged = prompt.split("## The files to judge", 1)[1].split("## Entities they cite", 1)[0]
files = re.findall(r'(?s)<file path="([^"]+)" kind="(\w+)">\n(.*?)\n</file>', judged)
MATERIAL = {"input": "cd /a", "reading_a": "A", "output_a": "cwd /a", "reading_b": "B", "output_b": "cwd unknown"}

# MATERIAL: a material finding in every sample. NOTE: a failing item with no material finding.
# SECOND: a material finding in the second sample only, as a judge with partial recall gives.
# SAME: a `material` whose two outputs are the same, which is no material finding.
def decide(kind, content, n):
    if "MATERIAL" in content or ("SECOND" in content and n == 2):
        return {"concrete": ("MOCK material", MATERIAL)}
    if "NOTE" in content:
        return {"mentions_complete": ("MOCK note", None)}
    if "SAME" in content:
        return {"concrete": ("MOCK same", dict(MATERIAL, output_b=MATERIAL["output_a"]))}
    return {}
out = {}
for path, kind, content in files:
    c = os.path.join(os.environ["CALLS"], path.replace("/", "_"))
    open(c, "a").write("x")
    fails = decide(kind, content, len(open(c).read()))
    ans = {}
    for i in items[kind]:
        if i in fails:
            ans[i] = {"ok": False, "evidence": fails[i][0]}
            if fails[i][1]:
                ans[i]["material"] = fails[i][1]
        else:
            ans[i] = {"ok": True, "evidence": "mock ok"}
    out[path] = {"probes": ["mock probe"], "items": ans}
print(json.dumps({"files": out}))
