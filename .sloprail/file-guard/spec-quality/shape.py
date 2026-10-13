#!/usr/bin/env python3
"""Deterministic: every spec file of the batch matches spec.cue (#Entity or #Invariant),
checked with sr-file validate; one verdict per file."""
import os, subprocess
import speclib as s

p = s.payload()
content = {f["path"]: f.get("newContent", "") for f in p["changeset"]["files"]}
schema = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spec.cue")
problems = {}
for path in s.subject_ids(p):
    kind = "#Invariant" if s.is_invariant(path) else "#Entity"
    r = subprocess.run(["sr-file", "validate", "-", "--as", "yaml", "--schema", schema, "--path", kind],
                       input=content.get(path, ""), capture_output=True, text=True)
    if r.returncode != 0:
        problems[path] = [f"{path} does not match spec.cue:\n{(r.stdout + r.stderr).strip()}"]
s.verdicts(p, problems)
