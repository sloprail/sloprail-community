#!/usr/bin/env python3
"""Hands the judge, once per batch: the two skills, the checklist (items.json), the spec's
entity catalog (speclib.catalog), the batch's files with their kind, the entities they cite,
and every invariant id of the spec. No other invariant: conflicts are spec-conflicts' check."""
import json, os
import speclib as s

p = s.payload()
head = p["changeset"]["head"]
members = s.subject_ids(p)
spec = s.spec_files_at(head, [s.spec_root(m) for m in members])
cited = sorted({e for m in members for e in s.cited_entities(spec.get(m, ""), s.spec_root(m))} - set(members))
items = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "items.json")))
print(json.dumps({"additionalContext": {
    "invariant_rules": s.at_head(head, s.SKILLS[0]) or "",
    "entity_rules": s.at_head(head, s.SKILLS[1]) or "",
    "checklist": {k: [{"name": n, "text": d} for n, d in v.items()] for k, v in items.items()},
    "catalog": "\n".join(s.catalog({k: v for k, v in spec.items() if k.startswith(r)}) for r in sorted({s.spec_root(m) for m in members})),
    "members": [{"path": m, "kind": "invariant" if s.is_invariant(m) else "entity", "content": spec.get(m, "")} for m in members],
    "cited": [{"path": e, "content": spec.get(e, "<missing>")} for e in cited],
    "index": sorted(s.inv_id(k) for k in spec if s.is_invariant(k)),
}}))
