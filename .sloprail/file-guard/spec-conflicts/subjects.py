#!/usr/bin/env python3
"""One subject per changed invariant, id = its path, batched by speclib.batches (clustered by
the fields they mention). Its verdict depends on its own text (the engine keys on its file) and
on this rule's files and speclib only, as a10n keys its conflict cache: editing one invariant
re-judges that one, not the invariants it shares a field with."""
import glob, hashlib, json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "spec-quality"))
import speclib as s

p = s.payload()
files = {f["path"]: f.get("newContent", "") for f in p["changeset"]["files"]
         if f.get("status") != "D" and s.is_invariant(f["path"])}
h = hashlib.sha256()
for own in sorted(glob.glob(os.path.join(here, "*")) + [os.path.join(here, "..", "spec-quality", "speclib.py")]):
    if os.path.isfile(own):
        h.update(os.path.basename(own).encode() + b"\0" + open(own, "rb").read() + b"\0")
fp = h.hexdigest()[:32]
out = []
for members in s.batches(files):
    bid = "batch-" + s.hash16(members)
    out += [{"id": m, "files": [m], "fingerprint": fp, "batch": bid} for m in members]
print(json.dumps(out))
