#!/usr/bin/env bash
set -euo pipefail
# spec-quality over a committed range of an example's spec, the document-invariant skill as
# committed in this repository.
# 1. the skill reaches the judge: the prompt carries its rule that an invariant is concrete.
# 2. an open-ended invariant ("valid shell syntax", no named grammar) is refused, with the
#    judge's reasoning naming its file.
# 3. its concrete neighbour, bounded by an entity that names the grammar, passes.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/line
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "One shell command line."\nfields:\n  - name: text\n    type: string\n    doc: "The line as written."\n  - name: parseError\n    type: string?\n    doc: "Why the line could not be read."\n' > "$S/entities/Line.yaml"
printf 'doc: "The shell language a line is read in: POSIX.1-2017 XCU chapter 2."\nfields:\n  - name: standard\n    type: string\n    doc: "The standard that defines it."\n    enum: ["POSIX.1-2017 XCU chapter 2"]\n' > "$S/entities/Grammar.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/spec-quality/judge": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --arg w "$1" 'any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="refused" and (.reason|contains($w)))' < "$SR_EVENTS_FILE" >/dev/null; }
passed() { jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="passed") and (any(.[]; .kind=="FileGuardChecked" and .rule=="spec-quality" and .outcome=="refused") | not)' "$SR_EVENTS_FILE" >/dev/null; }

# 1 and 2: the open-ended invariant
git checkout -q -b open "$BASE"
printf 'predicate: >-\n  A {@ent:line:Line} whose {@fld:line:Line.text} is valid shell syntax has no\n  {@fld:line:Line.parseError}.\nwhy: >-\n  A readable line would be flagged as unreadable.\n' > "$S/invariants/valid-line-has-no-parse-error.yaml"
commit open-ended
if run; then dump "2: an open-ended invariant passed"; fi
grep -q '^### An invariant is concrete' "$PROMPT_LOG" || dump "1: the skill's rule on concreteness is not in the judge's prompt"
refused "MOCK not concrete: $S/invariants/valid-line-has-no-parse-error.yaml" || dump "2: no refusal naming the open-ended invariant"

# 3: bounded by the grammar the spec defines, it passes
printf 'predicate: >-\n  A {@ent:line:Line} whose {@fld:line:Line.text} is written in the {@ent:line:Grammar}\n  has no {@fld:line:Line.parseError}.\nwhy: >-\n  A readable line would be flagged as unreadable.\n' > "$S/invariants/valid-line-has-no-parse-error.yaml"
commit concrete
run || dump "3: the concrete invariant was refused"
passed || dump "3: no passed verdict for the concrete invariant"
