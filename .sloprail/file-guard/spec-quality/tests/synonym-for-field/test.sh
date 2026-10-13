#!/usr/bin/env bash
set -euo pipefail
# The per-invariant judge gets the spec's entity catalog, each entity and field as its typed
# mention with its type and doc, and refuses an invariant that talks about a catalogued thing
# in other words, or relies on a value no entry holds.
# 1. the catalog reaches the prompt, with the field's token, type and doc.
# 2. "the directory a cd sets" for the catalogued Scope.cwd is refused, quoting the token to use.
# 3. "the umask", which nothing in the catalog holds, is refused as a missing field.
# 4. written with the token, it passes; run again unchanged, it is not judged again.
# 5. the catalog is in the verdict's key: a changed field doc judges it anew.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/sh
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "What a shell knows at one point of a line."\nfields:\n  - name: cwd\n    type: string?\n    doc: "The working directory there."\n' > "$S/entities/Scope.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)" OUT="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.py" '{"file-guard/spec-quality/judge": $p}')
run() { : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; echo "$1" >&2; exit 1; }
refused() { grep -qF "file-guard \"spec-quality\" $1: refused" "$OUT"; }
says() { grep -qF -- "$1" "$OUT"; }
F="$S/invariants/cd-moves.yaml"
inv() { printf 'predicate: >-\n  In a {@ent:sh:Scope}, %s\nwhy: >-\n  A command would be judged in the wrong place.\n' "$1" > "$F"; }

# 1 and 2: a synonym
inv 'after `cd DIR`, the directory a cd sets is DIR.'
commit synonym
if run; then dump "2: an invariant using a synonym for a catalogued field passed"; fi
grep -qF '  {@fld:sh:Scope.cwd} : string? — The working directory there.' "$PROMPT_LOG" || dump "1: the catalog is not in the prompt"
refused "$F" && says '- mentions_complete: MOCK synonym: "the directory a cd sets" is {@fld:sh:Scope.cwd}' || dump "2: no refusal quoting the token"

# 3: a missing field
inv 'after `umask 077`, the umask is 077.'
commit missing
if run; then dump "3: an invariant relying on an uncatalogued value passed"; fi
refused "$F" && says '- no_missing_field: MOCK missing field' || dump "3: no refusal naming the missing field"

# 4: the token
inv 'after `cd DIR`, the {@fld:sh:Scope.cwd} is DIR.'
commit token
run || dump "4: the invariant written with the token was refused"
grep -q '^## The files to judge' "$PROMPT_LOG" || dump "4: it was not judged"
run || dump "4: the second run was refused"
! grep -q '^## The files to judge' "$PROMPT_LOG" || dump "4: an unchanged invariant was judged again"

# 5: the catalog changes
sed -i 's/The working directory there./The working directory at that point./' "$S/entities/Scope.yaml"
commit doc
run || dump "5: refused after the doc change"
grep -q "<file path=\"$F\" kind=\"invariant\">" "$PROMPT_LOG" || dump "5: a catalog change did not judge the invariant anew"
