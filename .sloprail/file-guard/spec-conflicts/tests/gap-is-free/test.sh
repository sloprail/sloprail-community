#!/usr/bin/env bash
set -euo pipefail
# spec-conflicts under "unstated is unconstrained".
# 1. the prompt says a case neither invariant covers is never a finding.
# 2. two invariants on one field that decide different operations (unset, read) pass: the case
#    neither decides is a gap, not a conflict.
# 3. a second invariant that also decides unset is an overlap of two owners, and is refused.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-conflicts" "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/*/tests
# spec-quality is here for the speclib.py both share; it selects nothing in this case.
printf 'match: path matches "^-$"\nchecks:\n  - script: ./shape.py\n' > .sloprail/file-guard/spec-quality/file-guard.yaml
S=examples/demo/template/spec/v
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line; absent when the resolver does not know it."\n' > "$S/entities/Variable.yaml"
printf 'doc: "One place where the line changes a Variable."\nfields:\n  - name: kind\n    type: string\n    doc: "Its form."\n    enum: ["unset: an operand of unset", "read: an operand of read"]\n' > "$S/entities/Change.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)" OUT="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.py" '{"file-guard/spec-conflicts/judge": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; echo "$1" >&2; exit 1; }
refused() { grep -qF "file-guard \"spec-conflicts\" $S/invariants/$1.yaml: refused" "$OUT"; }
inv() { printf 'predicate: >-\n  %s\nwhy: >-\n  A wrong value would be reported.\n' "$2" > "$S/invariants/$1.yaml"; }

# 1 and 2: a gap between two owners passes
inv unset-empties 'Right after a {@ent:v:Change} whose {@fld:v:Change.kind} is unset, the Variable it names has the empty string as its {@fld:v:Variable.value}.'
inv read-is-unknown 'Right after a {@ent:v:Change} whose {@fld:v:Change.kind} is read, the Variable it names has no {@fld:v:Variable.value}.'
commit gap
run || dump "2: two invariants deciding different operations were refused"
grep -qF 'a case neither covers' "$PROMPT_LOG" || dump "1: the prompt does not say a gap is never a finding"

# 3: two owners of unset
inv unset-clears 'Right after a {@ent:v:Change} whose {@fld:v:Change.kind} is unset, the Variable it names has the empty string as its {@fld:v:Variable.value}, whatever it had.'
commit overlap
if run; then dump "3: two invariants deciding unset passed"; fi
refused unset-clears || dump "3: the second owner was not refused"
grep -qF "MOCK overlap" "$OUT" || dump "3: no refusal naming the overlap"
! grep -qF "MOCK gap" "$OUT" || dump "3: a gap was reported"
