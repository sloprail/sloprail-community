#!/usr/bin/env bash
set -euo pipefail
# givens-frozen over a committed range (the write got past the gate: a script, a generator).
# 1. a commit that changes an invariant is refused, naming it; 2. so is one that deletes an ADR,
# 3. adds an invariant, 4. changes CLAUDE.md. 5. a commit of code alone is not this rule's.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard spec/words/invariants adr/file-size internal/words
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/givens-frozen" .sloprail/file-guard/
rm -rf .sloprail/file-guard/givens-frozen/tests
printf 'predicate: original\n' > spec/words/invariants/a.yaml
printf 'limits: {go: 150}\n' > adr/file-size/ADR.md
printf 'the conventions\n' > CLAUDE.md
printf 'package words\n' > internal/words/a.go
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --arg w "$1" 'any(.[]; .kind=="FileGuardChecked" and .rule=="givens-frozen" and .outcome=="refused" and (.reason|contains("given and fixed")) and (.reason|contains($w)))' < "$SR_EVENTS_FILE" >/dev/null; }

git checkout -q -b weaken "$BASE"; printf 'predicate: weaker\n' > spec/words/invariants/a.yaml; commit weaken
if run; then dump "1: a changed invariant passed"; fi
refused "- spec/words/invariants/a.yaml (M)" || dump "1: no refusal naming the changed invariant"

git checkout -q -b drop "$BASE"; git rm -q adr/file-size/ADR.md; commit drop
if run; then dump "2: a deleted ADR passed"; fi
refused "- adr/file-size/ADR.md (D)" || dump "2: no refusal naming the deleted ADR"

git checkout -q -b add "$BASE"; printf 'predicate: new\n' > spec/words/invariants/new.yaml; commit add
if run; then dump "3: an added invariant passed"; fi
refused "- spec/words/invariants/new.yaml (A)" || dump "3: no refusal naming the added invariant"

git checkout -q -b claude "$BASE"; printf 'anything goes\n' > CLAUDE.md; commit claude
if run; then dump "4: a changed CLAUDE.md passed"; fi
refused "- CLAUDE.md (M)" || dump "4: no refusal naming CLAUDE.md"

git checkout -q -b code "$BASE"; printf 'package words\n\nfunc A() {}\n' > internal/words/a.go; printf 'notes\n' > README.md; commit code
run || dump "5: a commit of code and README.md was refused"
jq -es 'any(.[]; .rule=="givens-frozen" and .outcome=="refused") | not' < "$SR_EVENTS_FILE" >/dev/null || dump "5: the rule refused a commit that touches no given file"
