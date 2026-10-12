"""Shared by the spec-quality scripts: mentions, files at the range head, batches and neighbours.

The way a10n buckets invariants for its conflict check (a10n internal/specyaml/buckets.go):
every changed spec file is a subject of its own, keyed on its own content (and this rule), so
editing one invariant re-judges that one alone. Changed invariants are clustered by the fields
they mention (union-find) and packed into batches of up to BATCH judged files; each batch is shown, as
context it does not judge, its neighbours: other invariants of the spec that share a field (or,
more weakly, an entity, or an entity one field type away) with a judged one, ranked by how much
they share and capped so a call holds at most CAP invariants."""
import hashlib, json, re, subprocess, sys

MENTION = re.compile(r"\{@(ent|fld):([a-z0-9-]+):([A-Za-z0-9]+)(?:\.([A-Za-z0-9_]+))?\}")
SKILLS = [".claude/skills/document-invariant/SKILL.md", ".claude/skills/document-entity/SKILL.md"]
BATCH = 10
CAP = 30


def payload():
    return json.load(sys.stdin)


def subject_ids(p):
    """The ids this check decides: a batch's subjects, or the one subject."""
    if p.get("batch"):
        return [s["id"] for s in p["batch"]["subjects"]]
    return [p["subject"]["id"]]


def verdicts(p, problems):
    """Prints one verdict per subject id: problems is {id: [reason, ...]}."""
    ids = subject_ids(p)
    if p.get("batch"):
        print(json.dumps({"verdicts": {i: ({"pass": False, "reasoning": "\n".join(problems[i])} if problems.get(i) else {"pass": True}) for i in ids}}))
        return
    if problems.get(ids[0]):
        print(json.dumps({"reason": "\n".join(problems[ids[0]])}))
        sys.exit(1)


def _top():
    return subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()


def at_head(head, path):
    """The file as committed at head, or None when it does not exist there."""
    r = subprocess.run(["git", "-C", _top(), "show", f"{head}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def is_invariant(path):
    return "/invariants/" in path


def spec_root(path):
    """What precedes spec/ in a spec file's path: each example carries its own spec tree."""
    m = re.match(r"(.*?)spec/[a-z0-9-]+/(?:invariants|entities)/", path)
    return m.group(1) if m else ""


def entity_path(domain, entity, root=""):
    return f"{root}spec/{domain}/entities/{entity}.yaml"


def inv_id(path):
    m = re.match(r".*spec/([a-z0-9-]+)/invariants/([^/]+)\.yaml$", path)
    return f"{m.group(1)}/{m.group(2)}" if m else path


def mentions(text):
    """(kind, domain, entity, field) for every typed mention in text."""
    return [m.groups() for m in MENTION.finditer(text or "")]


def predicate(text):
    m = re.search(r"(?ms)^predicate:\s*(.*?)(?=^\S|\Z)", text or "")
    return m.group(1) if m else ""


def cited_entities(text, root=""):
    return sorted({entity_path(d, e, root) for _, d, e, _ in mentions(text)})


def hash16(parts):
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]


def spec_files_at(head, roots):
    """{path: content} of every spec file (invariants and entities) under the roots, at head."""
    out = {}
    for root in sorted(set(roots)):
        r = subprocess.run(["git", "-C", _top(), "ls-tree", "-r", "--name-only", head, "--", f"{root}spec/"],
                           capture_output=True, text=True)
        for path in r.stdout.split():
            if re.search(r"spec/[a-z0-9-]+/(invariants|entities)/[^/]+\.yaml$", path):
                out[path] = at_head(head, path) or ""
    return out


def field_types(entities):
    """{ "dom:Entity.field": "dom:Target" } for every field whose type is an entity."""
    out = {}
    for path, text in entities.items():
        m = re.match(r".*spec/([a-z0-9-]+)/entities/([A-Za-z0-9]+)\.yaml$", path)
        if not m:
            continue
        dom, ent = m.groups()
        for fm in re.finditer(r"(?m)^\s*-\s*name:\s*(\S+)\s*\n\s*type:\s*(\S+)", text):
            t = fm.group(2).strip("'\"").rstrip("?").replace("[]", "")
            tm = re.fullmatch(r"(?:([a-z0-9-]+)\.)?([A-Z][A-Za-z0-9]*)", t)
            if tm:
                out[f"{dom}:{ent}.{fm.group(1)}"] = f"{tm.group(1) or dom}:{tm.group(2)}"
    return out


def weighted_keys(text, root, types):
    """What an invariant's predicate touches, with a weight: a field it mentions 3, an entity it
    mentions 2, the entity of a field it mentions 1, the entity a mentioned field's type names 1."""
    w = {}
    def add(k, v):
        w[root + k] = max(w.get(root + k, 0), v)
    for kind, d, e, f in mentions(predicate(text)):
        if kind == "fld":
            add(f"{d}:{e}.{f}", 3)
            add(f"{d}:{e}", 1)
            if f"{d}:{e}.{f}" in types:
                add(types[f"{d}:{e}.{f}"], 1)
        else:
            add(f"{d}:{e}", 2)
    return w


def cluster_keys(text, root):
    """The keys changed invariants are clustered by: the fields they mention, or, for one that
    mentions no field, the entities it mentions."""
    ms = mentions(predicate(text))
    fl = {f"{root}{d}:{e}.{f}" for k, d, e, f in ms if k == "fld"}
    return fl or {f"{root}{d}:{e}" for k, d, e, f in ms}


def batches(changed):
    """changed: {path: content} of the changed spec files. Returns [[path, ...], ...]: invariants
    clustered by shared fields (union-find), each cluster ordered so the files of one field stay
    together, the clusters laid end to end (largest first) and the changed entities after them,
    packed greedily into batches of BATCH. A batch is only how files share a prompt: each keeps
    its own verdict, so small clusters fill one call instead of a call each."""
    invs = sorted(p for p in changed if is_invariant(p))
    parent = {p: p for p in invs}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    by_key = {}
    for p in invs:
        for k in cluster_keys(changed[p], spec_root(p)) or {p}:
            by_key.setdefault(k, []).append(p)
    for ms in by_key.values():
        for m in ms[1:]:
            parent[find(m)] = find(ms[0])
    clusters = {}
    for p in invs:
        clusters.setdefault(find(p), []).append(p)
    seq = []
    for c in sorted(clusters.values(), key=lambda c: (-len(c), c[0])):
        seen = set()
        for k, ms in sorted(by_key.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            for m in ms:
                if m in c and m not in seen:
                    seen.add(m); seq.append(m)
    seq += sorted(p for p in changed if not is_invariant(p))
    return [seq[i:i + BATCH] for i in range(0, len(seq), BATCH)]


def neighbours(members, spec):
    """The invariants of spec (at head) that are not members and share a weighted key with a
    member invariant, ranked by the summed weight of what they share (then by path), capped so
    members and neighbours hold at most CAP invariants."""
    types = field_types({p: t for p, t in spec.items() if not is_invariant(p)})
    mine = {}
    for m in members:
        if is_invariant(m):
            for k, v in weighted_keys(spec.get(m, ""), spec_root(m), types).items():
                mine[k] = max(mine.get(k, 0), v)
    scored = []
    for p, t in spec.items():
        if p in members or not is_invariant(p):
            continue
        theirs = weighted_keys(t, spec_root(p), types)
        s = sum(min(v, mine[k]) for k, v in theirs.items() if k in mine)
        if s > 0:
            scored.append((-s, p))
    room = max(0, CAP - sum(1 for m in members if is_invariant(m)))
    return [p for _, p in sorted(scored)[:room]]


def catalog(spec):
    """The entity catalog of a spec, one line per entity and per field: its typed-mention token,
    its type, and its doc on one line."""
    lines = []
    for path in sorted(k for k in spec if not is_invariant(k)):
        m = re.match(r".*spec/([a-z0-9-]+)/entities/([A-Za-z0-9]+)\.yaml$", path)
        if not m:
            continue
        dom, ent = m.groups()
        text = spec[path]
        dm = re.search(r"(?ms)^doc:\s*(?:>-\s*)?(.*?)(?=^\S|\Z)", text)
        doc = " ".join((dm.group(1) if dm else "").split()).strip('"')
        lines.append(f"{{@ent:{dom}:{ent}}} — {doc}")
        for fm in re.finditer(r"(?ms)^\s*-\s*name:\s*(\S+)\s*\n(.*?)(?=^\s*-\s*name:|\Z)", text):
            name, body = fm.group(1), fm.group(2)
            tm = re.search(r"(?m)^\s*type:\s*(\S+)", body)
            dd = re.search(r"(?m)^\s*doc:\s*(.*)$", body)
            fdoc = (dd.group(1).strip().strip('"') if dd else "")
            lines.append(f"  {{@fld:{dom}:{ent}.{name}}} : {tm.group(1) if tm else '?'} — {fdoc}")
    return "\n".join(lines)


def entity_names(spec):
    """{EntityName: "dom"} of the spec's entities."""
    out = {}
    for p in spec:
        m = re.match(r".*spec/([a-z0-9-]+)/entities/([A-Za-z0-9]+)\.yaml$", p)
        if m:
            out[m.group(2)] = m.group(1)
    return out
