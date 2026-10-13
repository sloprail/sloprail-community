#!/usr/bin/env python3
"""post_process: one verdict per judged invariant of the batch. Every judged invariant must be
answered, and only those, or the answer is sent back (exit 65); a finding whose other side is
not an invariant shown is sent back too. An invariant passes when it has no finding."""
import json, os, sys

answer = json.load(sys.stdin)
ctx = json.load(open(os.environ["SR_JUDGE_INPUT"]))["additionalContext"]
want = [m["path"] for m in ctx["members"]]
shown = set(want) | {n["path"] for n in ctx["neighbours"]}
got = answer.get("members") or {}
problems = [f"no entry for {p}" for p in want if p not in got] + [f"{p} is not an invariant to judge" for p in got if p not in want]
for p in want:
    for f in (got.get(p) or {}).get("findings", []):
        if f.get("with") not in shown or f.get("with") == p:
            problems.append(f"{p}: the finding's `with` {f.get('with')!r} is not another invariant shown")
if problems:
    print("; ".join(problems) + ". Answer every invariant under \"The invariants to judge\", naming the other side by its path.", file=sys.stderr)
    sys.exit(65)
out = {}
for p in want:
    fs = got[p]["findings"]
    out[p] = {"pass": not fs, "metadata": {"findings": fs, "summary": answer.get("summary", {}).get(p, "")}}
    if fs:
        out[p]["reasoning"] = f"{p}:\n" + "\n".join(
            f"- {f['kind']} with {f['with']}: {f['input']} — {f['explanation']} Fix: {f['fix']}" for f in fs)
print(json.dumps({"verdicts": out}))
