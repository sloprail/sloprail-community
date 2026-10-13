#!/usr/bin/env bash
set -euo pipefail
# The per-invariant judge applies document-entity to an invariant too, as it bears on the fields
# it mentions.
# 1. the document-entity rules reach the judge's prompt.
# 2. an invariant bounding one field's own value (a bound that belongs on the field) is refused
#    under entity_rules.
# 3. the bound moved onto the field, an invariant relying on it passes.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/v
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: name\n    type: string\n    doc: "Its name."\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line."\n' > "$S/entities/Variable.yaml"
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
F="$S/invariants/name-is-short.yaml"
printf 'predicate: >-\n  Every {@fld:v:Variable.name} is at most 64 bytes long.\nwhy: >-\n  A long name would be misread.\n' > "$F"
commit bound
if run; then dump "2: an invariant breaking an entity rule passed"; fi
grep -q '^### A value constraint lives in constraint_expr or enum, not prose' "$PROMPT_LOG" || dump "1: the document-entity rules are not in the prompt"
refused "$F" && says '- entity_rules: MOCK entity rule' || dump "2: no refusal under entity_rules"

git rm -q "$F"; mkdir -p "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: name\n    type: string\n    doc: "Its name."\n    constraint_expr: "size(this) <= 64"\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line."\n' > "$S/entities/Variable.yaml"
printf 'predicate: >-\n  A {@fld:v:Variable.name} written in a line names one {@ent:v:Variable}.\nwhy: >-\n  Two variables would be mixed up.\n' > "$S/invariants/name-names-one.yaml"
commit moved
run || dump "3: refused once the bound is on the field"
