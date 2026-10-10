"""Shared by the spec-quality scripts: mentions, files at the range head, bucketing."""
import hashlib, json, re, subprocess, sys

MENTION = re.compile(r"\{@(ent|fld):([a-z0-9-]+):([A-Za-z0-9]+)(?:\.([A-Za-z0-9_]+))?\}")
SKILLS = [".claude/skills/document-invariant/SKILL.md", ".claude/skills/document-entity/SKILL.md"]
MAX_MEMBERS = 25


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


def buckets(files):
    """files: {path: content}. Union-find over shared entities, then pack clusters into
    buckets of at most MAX_MEMBERS, splitting a larger cluster in order (a10n's
    clusterByEntity + splitNeighbours, validation mode)."""
    paths = sorted(files)
    parent = {p: p for p in paths}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    by_entity = {}
    for p in paths:
        keys = cited_entities(files[p], spec_root(p)) if is_invariant(p) else [p]
        for k in keys:
            by_entity.setdefault(k, []).append(p)
    for members in by_entity.values():
        for m in members[1:]:
            parent[find(m)] = find(members[0])
    groups = {}
    for p in paths:
        groups.setdefault(find(p), []).append(p)
    clusters = sorted(groups.values(), key=lambda g: g[0])

    out, cur = [], []
    for c in clusters:
        for i in range(0, len(c), MAX_MEMBERS):
            chunk = c[i:i + MAX_MEMBERS]
            if cur and len(cur) + len(chunk) > MAX_MEMBERS:
                out.append(cur)
                cur = []
            cur = cur + chunk
    if cur:
        out.append(cur)
    return out
