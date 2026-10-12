#!/usr/bin/env python3
# Mock judge for spec-conflicts. Keeps its prompt (PROMPT_LOG), then decides like the real one on
# two points. A gap (one invariant decides unset, another read, nothing says what unset then read
# leaves) is reported only when the prompt does not say that a case neither covers is never a
# finding. Two invariants that both decide unset are an overlap: reported as a duplicate on the
# judged side(s).
import json, os, re, sys
prompt = "".join(l for l in sys.stdin if not l.startswith('{"event":'))
open(os.environ["PROMPT_LOG"], "a").write(prompt)
part = lambda a, b: re.findall(r'(?s)<file path="([^"]+)">\n(.*?)\n</file>', prompt.split(a, 1)[1].split(b, 1)[0])
judged = part("## The invariants to judge", "## Neighbours")
shown = judged + part("## Neighbours", "## Entities they cite")
unset = [p for p, c in shown if "Change.kind} is unset" in c]
read = [p for p, c in shown if "Change.kind} is read" in c]
gap_free = "a case neither covers" in prompt
members, summary = {}, {p: "mock" for p, _ in shown}
for p, c in judged:
    f = [{"with": o, "kind": "duplicate", "input": "unset X", "explanation": "MOCK overlap: both decide unset", "fix": "mock"} for o in unset if p in unset and o != p]
    if not gap_free:
        f += [{"with": o, "kind": "conflict", "input": "unset X; read X", "explanation": "MOCK gap: nothing decides the value after both", "fix": "mock"} for o in (read if p in unset else unset if p in read else [])]
    members[p] = {"findings": f}
print(json.dumps({"summary": summary, "members": members}))
