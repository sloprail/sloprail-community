#!/usr/bin/env bash
set -euo pipefail
# spec-quality groups invariants by the fields they mention, not by name or by the entity they
# cite, and checks each pair that shares a field.
# 1. two conflicting invariants on Variable.value, named far apart (a-…, z-…) with 26 others
#    that cite Variable between them, are judged together and refused: under the old grouping
#    (union-find on the cited entity, cut into alphabetical slices of 25) they never met.
# 2. a change to one of them alone is still refused: the other comes along as a related,
#    unchanged invariant.
# 3. once they agree, the spec passes.
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
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/spec-quality/judge": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; : > "$PROMPT_LOG"; sr-checks run --base "$1" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --arg w "$1" 'any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="refused" and (.reason|contains($w)))' < "$SR_EVENTS_FILE" >/dev/null; }
passed() { jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="passed") and (any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="refused") | not)' "$SR_EVENTS_FILE" >/dev/null; }
inv() { printf 'predicate: >-\n  %s\nwhy: >-\n  %s\n' "$2" "A wrong value would be reported." > "$S/invariants/$1.yaml"; }

# 1: the pair, 26 invariants apart
inv a-unset-empties 'Right after `unset NAME`, the Variable NAME has the empty string as its {@fld:v:Variable.value}.'
for i in $(seq -w 1 26); do inv "m-filler-$i" "A {@ent:v:Variable} whose {@fld:v:Variable.name} is N$i is told apart from every other."; done
inv z-unset-keeps 'Right after `unset NAME`, the Variable NAME keeps the value it had as its {@fld:v:Variable.value}.'
commit pair
if run "$BASE"; then dump "1: two conflicting invariants on one field passed"; fi
refused "MOCK conflict" || dump "1: no refusal naming the conflict"

# 2: only z changes; a comes along as a related invariant
MID=$(git rev-parse HEAD)
inv z-unset-keeps 'Right after `unset NAME`, the Variable NAME keeps the value it had as its {@fld:v:Variable.value}, there.'
commit z-only
if run "$MID"; then dump "2: a changed invariant conflicting with an unchanged one passed"; fi
grep -q '## Related invariants' "$PROMPT_LOG" || dump "2: no related invariants in the prompt"
refused "MOCK conflict" || dump "2: no refusal naming the conflict with the related invariant"

# 3: they agree
inv z-unset-keeps 'Right after `unset NAME`, the Variable NAME has the empty string as its {@fld:v:Variable.value}, there.'
commit agree
run "$BASE" || dump "3: agreeing invariants were refused"
passed || dump "3: no passed verdict"
