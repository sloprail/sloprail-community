#!/usr/bin/env python3
"""post_process: the judge's checklist (response.schema.json, items.json) becomes one verdict per
file of the batch. Every file must be answered, and every item of its kind's checklist, or the
answer is sent back (exit 65). A file is refused only for a material finding: a failing item
that gives a concrete input inside the boundary and two readings requiring different outputs; any
other failing item is a note (metadata.notes) and does not block. metadata: the items, as answered."""
import json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
items = json.load(open(os.path.join(here, "items.json")))
answer = json.load(sys.stdin)
given = json.load(open(os.environ["SR_JUDGE_INPUT"]))
want = {m["path"]: m["kind"] for m in given["additionalContext"]["members"]}
got = answer.get("files") or {}
problems = [f"no entry for {p}" for p in want if p not in got] + [f"{p} is not a file you were given" for p in got if p not in want]
for p, kind in want.items():
    if p in got:
        missing = [i for i in items[kind] if i not in got[p].get("items", {})]
        if missing:
            problems.append(f"{p} lacks the items {', '.join(missing)}")
if problems:
    print("; ".join(problems) + ". Answer every file under \"The files to judge\", and every item of its kind's checklist.", file=sys.stderr)
    sys.exit(65)
out = {}
for p, kind in want.items():
    ans = got[p]["items"]
    def material(a):
        m = a.get("material") or {}
        return all((m.get(k) or "").strip() for k in ("input", "reading_a", "output_a", "reading_b", "output_b")) \
            and m["output_a"].strip() != m["output_b"].strip()
    blocking = [i for i in items[kind] if not ans[i]["ok"] and material(ans[i])]
    fails = [f"- {i}: {ans[i]['evidence']} Input: {ans[i]['material']['input']}; one reading requires {ans[i]['material']['output_a']}, the other {ans[i]['material']['output_b']}." for i in blocking]
    notes = [f"{i}: {ans[i]['evidence']}" for i in items[kind] if not ans[i]["ok"] and i not in blocking]
    out[p] = {"pass": not fails, "metadata": {"items": ans, "notes": notes}}
    if fails:
        out[p]["reasoning"] = f"{p}:\n" + "\n".join(fails)
print(json.dumps({"verdicts": out}))
