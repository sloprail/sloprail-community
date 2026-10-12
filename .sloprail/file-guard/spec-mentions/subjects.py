#!/usr/bin/env python3
"""One subject per spec tree the change touches (an example's spec/), id `spec-mentions:<root>`;
its fingerprint is every spec file of that tree at head, this rule's files and speclib."""
import glob, hashlib, json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "spec-quality"))
import speclib as s

p = s.payload()
head = p["changeset"]["head"]
roots = sorted({s.spec_root(f.get("oldPath") or f["path"]) for f in p["changeset"]["files"]} |
               {s.spec_root(f["path"]) for f in p["changeset"]["files"]})
out = []
for root in roots:
    h = hashlib.sha256()
    for own in sorted(glob.glob(os.path.join(here, "*")) + [os.path.join(here, "..", "spec-quality", "speclib.py")]):
        if os.path.isfile(own):
            h.update(os.path.basename(own).encode() + b"\0" + open(own, "rb").read() + b"\0")
    for path, text in sorted(s.spec_files_at(head, [root]).items()):
        h.update(path.encode() + b"\0" + text.encode() + b"\0")
    out.append({"id": f"spec-mentions:{root}", "fingerprint": h.hexdigest()[:32]})
print(json.dumps(out))
