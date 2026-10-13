#!/usr/bin/env python3
# Mock judge for spec-conflicts. Keeps its prompt (PROMPT_LOG), then decides like the real one on
# one point: after `unset NAME`, one invariant empties the value and another keeps it. It sees a
# pair only when both stand in its prompt (judged, or among the neighbours), and reports it on
# the judged side(s) only, so a check that split the pair or judged neighbours fails the case.
import json, os, re, sys
prompt = "".join(l for l in sys.stdin if not l.startswith('{"event":'))
open(os.environ["PROMPT_LOG"], "a").write(prompt)
part = lambda a, b: re.findall(r'(?s)<file path="([^"]+)">\n(.*?)\n</file>', prompt.split(a, 1)[1].split(b, 1)[0])
judged = part("## The invariants to judge", "## Neighbours")
near = part("## Neighbours", "## Entities they cite")
shown = judged + near
empties = [p for p, c in shown if "has the empty string as its" in c]
keeps = [p for p, c in shown if "keeps the value it had" in c]
members, summary = {}, {p: "mock" for p, _ in shown}
for p, c in judged:
    others = keeps if p in empties else empties if p in keeps else []
    members[p] = {"findings": [{"with": o, "kind": "conflict", "input": "unset X", "explanation": "MOCK conflict on Variable.value", "fix": "mock"} for o in others]}
print(json.dumps({"summary": summary, "members": members}))
