#!/usr/bin/env bash
set -euo pipefail
# The judge answers every item of a fixed checklist for every file of its batch
# (response.schema.json, items.json), and post-process.py makes one verdict per file.
# 1. the prompt asks to answer every item, not to stop at the first failing one, and lists the
#    checklist.
# 2. three flawed invariants, each judged in its own call, are refused one by one, each listing both of
#    its failing items.
# 3. an answer that leaves a judged file out, or an item of one, is rejected as unusable, naming
#    that file.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/v
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line."\n' > "$S/entities/Variable.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)" OUT="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.py" '{"file-guard/spec-quality/judge": $p}')
dump() { cat "$OUT" >&2; echo "$1" >&2; exit 1; }
for n in one two three; do
  printf 'predicate: >-\n  BAD: the {@fld:v:Variable.value} is %s.\nwhy: >-\n  A wrong value would be reported.\n' "$n" > "$S/invariants/$n.yaml"
done
git add -A && git -c user.name=t -c user.email=t@t commit -q -m three
: > "$SR_EVENTS_FILE"
if sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; then dump "2: three flawed invariants passed"; fi
grep -q 'do not stop at the first failing item' "$PROMPT_LOG" || dump "1: the prompt does not ask for every item"
grep -q '^- `mentions_complete`' "$PROMPT_LOG" || dump "1: the checklist is not in the prompt"
[ "$(grep -c 'judged "spec-quality"' "$OUT")" -ge 3 ] || dump "2: the three invariants were not judged one to a call"
for n in one two three; do
  grep -qF "file-guard \"spec-quality\" $S/invariants/$n.yaml: refused" "$OUT" || dump "2: $n was not refused on its own"
  awk -v p="  - $S/invariants/$n.yaml:" '$0==p{on=1;next} on&&/^  - /{on=0} on' "$OUT" > "$OUT.$n"
  grep -q '^- concrete: MOCK bad concrete' "$OUT.$n" && grep -q '^- decidable: MOCK bad decidable' "$OUT.$n" || dump "2: the refusal of $n does not list both items"
done
printf 'predicate: >-\n  BAD: the {@fld:v:Variable.value} is four.\nwhy: >-\n  A wrong value would be reported.\n' > "$S/invariants/two.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m omit
: > "$SR_EVENTS_FILE"
if OMIT=1 sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; then dump "3: an answer missing a file passed"; fi
grep -qF "no entry for $S/invariants/two.yaml" "$OUT" || dump "3: the answer missing a judged file was not rejected naming it"
printf 'predicate: >-\n  BAD: the {@fld:v:Variable.value} is five.\nwhy: >-\n  A wrong value would be reported.\n' > "$S/invariants/two.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m drop
: > "$SR_EVENTS_FILE"
if DROP_ITEM=two.yaml sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; then dump "3: an answer missing an item passed"; fi
grep -qF "$S/invariants/two.yaml lacks the items" "$OUT" || dump "3: the answer missing an item was not rejected naming the file"
