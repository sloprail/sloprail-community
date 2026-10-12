"""Shared by the spec-quality scripts: mentions, files at the range head, grouping by field."""
import hashlib, json, re, subprocess, sys

MENTION = re.compile(r"\{@(ent|fld):([a-z0-9-]+):([A-Za-z0-9]+)(?:\.([A-Za-z0-9_]+))?\}")
SKILLS = [".claude/skills/document-invariant/SKILL.md", ".claude/skills/document-entity/SKILL.md"]
MAX_MEMBERS = 30
HARD_MAX = 60


def payload():
    return json.load(sys.stdin)


def at_head(head, path):
    """The file as committed at head, or None when it does not exist there."""
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
    r = subprocess.run(["git", "-C", top, "show", f"{head}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def is_invariant(path):
    return "/invariants/" in path


def spec_root(path):
    """What precedes spec/ in a spec file's path: each example carries its own spec tree."""
    m = re.match(r"(.*?)spec/[a-z0-9-]+/(?:invariants|entities)/", path)
    return m.group(1) if m else ""


def entity_path(domain, entity, root=""):
    return f"{root}spec/{domain}/entities/{entity}.yaml"


def mentions(text):
    """(kind, domain, entity, field) for every typed mention in text."""
    return [m.groups() for m in MENTION.finditer(text or "")]


def cited_entities(text, root=""):
    return sorted({entity_path(d, e, root) for _, d, e, _ in mentions(text)})


def hash16(parts):
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]


def keys(text, root=""):
    """What an invariant constrains: every field and every entity it mentions."""
    out = set()
    for kind, d, e, f in mentions(text):
        out.add(f"{root}{d}:{e}.{f}" if kind == "fld" else f"{root}{d}:{e}")
    return out


def invariants_at(head, roots):
    """{path: content} of every invariant under the given spec roots, as committed at head."""
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
    out = {}
    for root in sorted(set(roots)):
        r = subprocess.run(["git", "-C", top, "ls-tree", "-r", "--name-only", head, "--", f"{root}spec/"],
                           capture_output=True, text=True)
        for path in r.stdout.split():
            if is_invariant(path) and path.endswith(".yaml"):
                out[path] = at_head(head, path) or ""
    return out


def index(head, members):
    """Every invariant id (<domain>/<name>) of the spec trees the members belong to, at head."""
    out = []
    for path in invariants_at(head, [spec_root(m) for m in members]):
        m = re.match(r".*spec/([a-z0-9-]+)/invariants/([^/]+)\.yaml$", path)
        if m:
            out.append(f"{m.group(1)}/{m.group(2)}")
    return sorted(out)


def related(head, members, files):
    """Invariants at head that are not in the change but mention a field or entity a member
    invariant mentions: the judge checks the members against them for conflicts."""
    mine = set()
    for m in members:
        if is_invariant(m):
            mine |= keys(files[m], spec_root(m))
    if not mine:
        return {}
    roots = [spec_root(m) for m in members]
    return {p: t for p, t in invariants_at(head, roots).items()
            if p not in files and keys(t, spec_root(p)) & mine}


def buckets(files):
    """files: {path: content}. Groups by what the invariants constrain, not by alphabet: for
    every field or entity, ALL the changed invariants that mention it land in one group, so a
    judge sees every pair that could conflict on it side by side (one invariant may be in
    several groups). Keys are taken largest first; a key's invariants join the group they
    overlap most while it stays within MAX_MEMBERS, else open a new group; a key holding more
    than HARD_MAX invariants is cut into slices of that size. An entity file joins the group
    whose invariants cite it most."""
    invs = sorted(p for p in files if is_invariant(p))
    by_key = {}
    for p in invs:
        for k in keys(files[p], spec_root(p)) or {p}:
            by_key.setdefault(k, set()).add(p)
    groups = []
    for k, g in sorted(by_key.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        if any(g <= x for x in groups):
            continue
        if len(g) > HARD_MAX:
            gl = sorted(g)
            groups += [set(gl[i:i + HARD_MAX]) for i in range(0, len(gl), HARD_MAX)]
            continue
        best = None
        for x in groups:
            if len(x | g) <= MAX_MEMBERS and (best is None or (len(x & g), -len(x)) > (len(best & g), -len(best))):
                best = x
        if best is not None:
            best |= g
        else:
            groups.append(set(g))
    loose = []
    for e in sorted(p for p in files if not is_invariant(p)):
        score = [sum(1 for m in x if e in cited_entities(files[m], spec_root(m))) for x in groups]
        if score and max(score) > 0:
            groups[score.index(max(score))].add(e)
        else:
            loose.append(e)
    for i in range(0, len(loose), MAX_MEMBERS):
        groups.append(set(loose[i:i + MAX_MEMBERS]))
    return sorted((sorted(x) for x in groups), key=lambda x: x[0])
