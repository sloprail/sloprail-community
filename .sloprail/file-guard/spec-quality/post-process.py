#!/usr/bin/env python3
"""post_process: the judge's per-file findings (response.schema.json) become the group's verdict.

stdin           {files: {"<path>": {checked, findings: [{rule, ids, input, fix}]}}}
SR_JUDGE_INPUT  what the prompt was rendered with: additionalContext.members are the judged files

Every judged file must have an entry and no other file may: otherwise exit 65 and the judge is
asked again. The group passes when no file has a finding; the reasoning lists every finding,
one per line, so the agent sees all of them at once. metadata: the number of findings per file."""
import json, os, sys

answer = json.load(sys.stdin)
given = json.load(open(os.environ["SR_JUDGE_INPUT"]))
want = [m["path"] for m in given["additionalContext"]["members"]]
got = answer.get("files") or {}
problems = [f"no entry for {p}" for p in want if p not in got] + [f"{p} is not a file you were given" for p in got if p not in want]
if problems:
    print("; ".join(problems) + ". Give one entry in `files` for each file under \"The files to judge\", and for no other.", file=sys.stderr)
    sys.exit(65)
lines = []
for p in want:
    for f in got[p]["findings"]:
        lines.append(f"- {p} [{f['rule']}] ({', '.join(f['ids'])}): {f['input']} -> {f['fix']}")
print(json.dumps({
    "pass": not lines,
    "reasoning": f"{len(lines)} finding(s):\n" + "\n".join(lines) if lines else "",
    "metadata": {"findings": {p: len(got[p]["findings"]) for p in want}},
}))
