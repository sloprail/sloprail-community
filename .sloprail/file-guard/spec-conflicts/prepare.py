#!/usr/bin/env python3
"""Hands the judge, once per batch: the batch's invariants (judged), their neighbours at head
(other invariants sharing a field, an entity, or an entity one field type away; ranked and
capped by speclib.neighbours; context, not judged), the entities either cites, and every
invariant id of the spec."""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "spec-quality"))
import speclib as s

p = s.payload()
head = p["changeset"]["head"]
members = s.subject_ids(p)
spec = s.spec_files_at(head, [s.spec_root(m) for m in members])
near = s.neighbours(members, spec)
cited = sorted({e for m in members + near for e in s.cited_entities(spec.get(m, ""), s.spec_root(m))})
print(json.dumps({"additionalContext": {
    "members": [{"path": m, "content": spec.get(m, "")} for m in members],
    "neighbours": [{"path": n, "content": spec[n]} for n in near],
    "cited": [{"path": e, "content": spec.get(e, "<missing>")} for e in cited],
    "index": sorted(s.inv_id(k) for k in spec if s.is_invariant(k)),
}}))
