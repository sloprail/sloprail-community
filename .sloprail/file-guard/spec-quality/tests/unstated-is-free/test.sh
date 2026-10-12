#!/usr/bin/env bash
set -euo pipefail
# Unstated is unconstrained: an invariant states its own boundary and need not be complete.
# 1. the principle reaches the judge, from the skill and from the prompt's own rule of evidence.
# 2. an invariant that decides what unset does, and leaves what read does unstated, passes: a gap
#    is not refused.
# 3. an invariant whose boundary rests on a word two readers apply apart is refused.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/v
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line; absent when the resolver does not know it."\n' > "$S/entities/Variable.yaml"
printf 'doc: "One place where the line changes a Variable."\nfields:\n  - name: kind\n    type: string\n    doc: "Its form."\n    enum: ["unset: an operand of unset", "read: an operand of read"]\n' > "$S/entities/Change.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.py" '{"file-guard/spec-quality/judge": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --arg w "$1" 'any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="refused" and (.reason|contains($w)))' < "$SR_EVENTS_FILE" >/dev/null; }
inv() { printf 'predicate: >-\n  %s\nwhy: >-\n  A wrong value would be reported.\n' "$2" > "$S/invariants/$1.yaml"; }

# 1 and 2: a gap passes
inv unset-empties 'Right after a {@ent:v:Change} whose {@fld:v:Change.kind} is unset, the Variable it names has the empty string as its {@fld:v:Variable.value}.'
commit gap
run || dump "2: an invariant that leaves another operation unstated was refused"
grep -q '^## Unstated is unconstrained' "$PROMPT_LOG" || dump "1: the principle is not in the judge's prompt"
grep -q 'A gap is never a$' "$PROMPT_LOG" || dump "1: the prompt does not say a gap is never a finding"

# 3: an unclear boundary is refused
inv export-reaches 'An export of a {@ent:v:Variable} the line assigned gives later programs its {@fld:v:Variable.value}.'
commit unclear
if run; then dump "3: an invariant with an unclear boundary passed"; fi
refused "- concrete: MOCK boundary" && refused "$S/invariants/export-reaches.yaml:" || dump "3: no refusal naming the unclear boundary"
! refused "$S/invariants/unset-empties.yaml:" || dump "3: the bounded invariant was refused"
