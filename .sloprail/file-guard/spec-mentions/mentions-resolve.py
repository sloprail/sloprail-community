#!/usr/bin/env python3
"""The whole spec tree of the subject, at head: every invariant has a predicate with at least
one typed mention; every mention resolves to an entity file and, for a field, a field it
declares; and outside its mentions a predicate names no entity of the spec (capitalised, alone,
plural or with a .field): that is a modelled thing written as a synonym."""
import json, os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "spec-quality"))
import speclib as s

p = s.payload()
head = p["changeset"]["head"]
root = p["subject"]["id"].split(":", 1)[1]
spec = s.spec_files_at(head, [root])
names = s.entity_names(spec)
bad = []
for path in sorted(k for k in spec if s.is_invariant(k)):
    pred = s.predicate(spec[path])
    if not pred.strip():
        bad.append(f"{path}: no predicate")
        continue
    ms = s.mentions(pred)
    if not ms:
        bad.append(f"{path}: the predicate names no {{@ent:...}} or {{@fld:...}}")
    for kind, dom, ent, fld in ms:
        epath = s.entity_path(dom, ent, root)
        etext = spec.get(epath)
        token = f"{{@{kind}:{dom}:{ent}{'.' + fld if fld else ''}}}"
        if etext is None:
            bad.append(f"{path}: {token} names an entity with no {epath}")
        elif kind == "fld" and not re.search(r"(?m)^\s*-\s*name:\s*" + re.escape(fld or "") + r"\s*$", etext):
            bad.append(f"{path}: {token} names a field {epath} does not declare")
    plain = s.MENTION.sub(" ", pred)
    for name in sorted(names):
        for m in re.finditer(r"(?<![\w./:{@`-])" + re.escape(name) + r"(s?)(\.[A-Za-z_][A-Za-z0-9_]*)?(?![\w])", plain):
            fix = f"{{@ent:{names[name]}:{name}}}" + (f" or {{@fld:{names[name]}:{name}{m.group(2)}}}" if m.group(2) else "")
            bad.append(f"{path}: `{m.group(0)}` names a modelled thing in plain words; write {fix}")
if bad:
    print(json.dumps({"reason": "Spec mentions that do not hold, over the whole spec at head:\n" + "\n".join(bad)}))
    sys.exit(1)
