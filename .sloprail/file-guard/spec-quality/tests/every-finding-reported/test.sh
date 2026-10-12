#!/usr/bin/env bash
set -euo pipefail
# The judge answers one entry per judged file with every finding (response.schema.json), and
# post-process.py turns that into the verdict.
# 1. the prompt asks for every finding, not the first.
# 2. three flawed invariants in one group give one refusal listing all three findings.
# 3. an answer that leaves a judged file out is rejected as unusable, naming that file.
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
export PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/spec-quality/judge": $p}')
dump() { jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --arg w "$1" 'any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="refused" and (.reason|contains($w)))' < "$SR_EVENTS_FILE" >/dev/null; }
for n in one two three; do
  printf 'predicate: >-\n  BAD: the {@fld:v:Variable.value} is %s.\nwhy: >-\n  A wrong value would be reported.\n' "$n" > "$S/invariants/$n.yaml"
done
git add -A && git -c user.name=t -c user.email=t@t commit -q -m three
: > "$SR_EVENTS_FILE"
if sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; then dump "2: three flawed invariants passed"; fi
grep -q 'Be exhaustive' "$PROMPT_LOG" || dump "1: the prompt does not ask for every finding"
refused "3 finding(s)" || dump "2: the refusal does not count three findings"
for n in one two three; do refused "$S/invariants/$n.yaml [mock]" || dump "2: no finding for $n"; done
printf 'predicate: >-\n  BAD: the {@fld:v:Variable.value} is four.\nwhy: >-\n  A wrong value would be reported.\n' > "$S/invariants/two.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m omit
: > "$SR_EVENTS_FILE"
if OMIT=1 sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; then dump "3: an answer missing a file passed"; fi
refused "no entry for $S/invariants/two.yaml" || dump "3: the answer missing a judged file was not rejected naming it"
