#!/usr/bin/env bash
set -euo pipefail
# spec-quality over a committed range of an example's spec, the document-invariant skill as
# committed in this repository.
# 1. the skill reaches the judge: the prompt carries its rule that an invariant asks only for
#    what a program can decide.
# 2. an invariant that asks for every program a string runs, strings inside strings included,
#    with no bound, is refused with the judge's reasoning naming its file.
# 3. the same invariant with the bound stated (a depth past which the string has no text)
#    passes.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/cs
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "An argument a program runs as a shell command line of its own."\nfields:\n  - name: text\n    type: string?\n    doc: "The string; absent exactly where an invariant of this domain says it has none."\n  - name: depth\n    type: int32\n    doc: "How many command strings it stands inside."\n' > "$S/entities/CommandString.yaml"
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
F="$S/invariants/command-string-is-resolved-as-a-line.yaml"

# 1 and 2: no bound
printf 'predicate: >-\n  A {@ent:cs:CommandString} whose {@fld:cs:CommandString.text} is known yields the Invocations its text holds.\nwhy: >-\n  `bash -c npm` would hide npm.\n' > "$F"
commit unbounded
if run; then dump "2: an undecidable invariant passed"; fi
grep -q 'an invariant asks only for what a program can decide' "$PROMPT_LOG" || dump "1: the skill's rule on deciding is not in the judge's prompt"
refused "MOCK undecidable: $F" || dump "2: no refusal naming the undecidable invariant"

# 3: the bound stated
printf 'predicate: >-\n  A {@ent:cs:CommandString} whose {@fld:cs:CommandString.text} is known and whose\n  {@fld:cs:CommandString.depth} is at most 3 yields the Invocations its text holds; past that\n  depth it has no text.\nwhy: >-\n  `bash -c npm` would hide npm.\n' > "$F"
commit bounded
run || dump "3: the bounded invariant was refused"
passed || dump "3: no passed verdict for the bounded invariant"
