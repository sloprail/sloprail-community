#!/usr/bin/env python3
"""One subject per changed spec file, id = its path, batched five to a call by speclib.batches
(a judge answering the checklist for ten files missed real faults a later call found). Its verdict
depends on its own content (the engine keys on its files) and on its fingerprint: this rule's
files, the two skills, the entities it cites and the spec's entity catalog, as at head. An
entity change thus re-judges a changed file against it; an unchanged invariant is not a
subject here (spec-mentions checks every mention of the whole spec)."""
import glob, hashlib, json, os
import speclib as s

p = s.payload()
head = p["changeset"]["head"]
files = {f["path"]: f.get("newContent", "") for f in p["changeset"]["files"] if f.get("status") != "D"}
here = os.path.dirname(os.path.abspath(__file__))
base = hashlib.sha256()
for own in sorted(f for f in glob.glob(os.path.join(here, "*")) if os.path.isfile(f)):
    base.update(os.path.basename(own).encode() + b"\0" + open(own, "rb").read() + b"\0")
for path in s.SKILLS:
    base.update(path.encode() + b"\0" + (s.at_head(head, path) or "<absent>").encode() + b"\0")
specs = {}
out = []
for members in s.batches(files, s.QUALITY_BATCH):
    bid = "batch-" + s.hash16(members)
    for m in members:
        root = s.spec_root(m)
        if root not in specs:
            specs[root] = s.spec_files_at(head, [root])
        h = base.copy()
        h.update(s.catalog(specs[root]).encode() + b"\0")
        for e in s.cited_entities(files[m], root):
            h.update(e.encode() + b"\0" + specs[root].get(e, "<absent>").encode() + b"\0")
        out.append({"id": m, "files": [m], "fingerprint": h.hexdigest()[:32], "batch": bid})
print(json.dumps(out))
