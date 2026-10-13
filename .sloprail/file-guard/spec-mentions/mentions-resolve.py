#!/usr/bin/env python3
"""The whole spec tree of the subject, at head: every invariant has a predicate with at least
one typed mention; every mention resolves to an entity file and, for a field, a field it
declares; and outside its mentions a predicate names no entity of the spec (capitalised, alone,
plural or with a .field): that is a modelled thing written as a synonym. Nor does it read a field
by its bare name (`whose text`, `its name`) where it mentions the field's entity but no field of
that name: a later reference by the field's own name is fine only after its mention, and an
entity often has two fields such a phrase could mean."""
import json, os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "spec-quality"))
import speclib as s

p = s.payload()
head = p["changeset"]["head"]
root = p["subject"]["id"].split(":", 1)[1]
spec = s.spec_files_at(head, [root])
names = s.entity_names(spec)
fields = {}
for epath, etext in spec.items():
    em = re.match(r".*spec/([a-z0-9-]+)/entities/([A-Za-z0-9]+)\.yaml$", epath)
    if em:
        fields[em.groups()] = re.findall(r"(?m)^\s*-\s*name:\s*(\S+)\s*$", etext)
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
    named = {fld for _, _, _, fld in ms if fld}
    loose = {}
    for dom, ent in sorted({(d, e) for _, d, e, _ in ms}):
        for fld in fields.get((dom, ent), []):
            if fld in named:
                continue
            for m in re.finditer(r"\b(?:whose|its|their)\s+" + re.escape(fld) + r"\b(?!\s+word)", plain):
                loose.setdefault(m.group(0), []).append(f"{{@fld:{dom}:{ent}.{fld}}}")
    for words, tokens in sorted(loose.items()):
        bad.append(f"{path}: `{words}` reads a field the predicate never mentions; write {' or '.join(sorted(set(tokens)))}")
if bad:
    print(json.dumps({"reason": "Spec mentions that do not hold, over the whole spec at head:\n" + "\n".join(bad)}))
    sys.exit(1)
