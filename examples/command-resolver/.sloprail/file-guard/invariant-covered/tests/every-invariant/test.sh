#!/usr/bin/env bash
set -euo pipefail
# invariant-covered over a committed range, each refusal beside its nearest permitted neighbour.
# The spec is given whole: demo/a is implemented and proven at the base, demo/b is neither.
# 1. EVERY invariant is checked: a commit of unmarked Go is refused naming both missing halves of
#    demo/b, which the commit never touched; once demo/b is marked, the same range passes.
# 2. deleting the only test proving demo/a is refused.
# 3. a marker naming no invariant is refused naming the missing spec file.
# 4. sr:proves on code (not a test) is refused.
# 5. a long list is cut: with 20 uncovered invariants the refusal shows 30 lines and counts the rest.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard src
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/invariant-covered" .sloprail/file-guard/
rm -rf .sloprail/file-guard/invariant-covered/tests
inv() { mkdir -p "spec/demo/invariants"; printf 'predicate: A {@fld:demo:Thing.on} thing %s holds.\nwhy: w\n' "$1" > "spec/demo/invariants/$1.yaml"; }
inv a; inv b
printf 'package src\n\n// sr:invariant demo/a\nfunc A() {}\n' > src/a.go
printf 'package src\n\n// sr:proves demo/a\nfunc TestA(t *testing.T) {}\n' > src/a_test.go
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --args 'any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-covered" and .outcome=="refused" and (.reason as $r | $ARGS.positional | all(. as $w | $r | contains($w))))' "$@" < "$SR_EVENTS_FILE" >/dev/null; }
passed() { jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-covered" and .outcome=="passed") and (any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-covered" and .outcome=="refused") | not)' "$SR_EVENTS_FILE" >/dev/null; }

# 1. every invariant, touched or not
git checkout -q -b unmarked "$BASE"
printf 'package src\n\nfunc Helper() {}\n' > src/helper.go
commit unmarked-code
if run; then dump "1: demo/b has no markers and the commit passed"; fi
refused "Invariants not implemented or not proven (2)" "invariant 'demo/b' has no implementation" "invariant 'demo/b' has no test" || dump "1: no refusal naming both missing halves of demo/b"
if refused "invariant 'demo/a'"; then dump "1: demo/a, covered, was reported"; fi
printf 'package src\n\n// sr:invariant demo/b\nfunc B() {}\n' > src/b.go
printf 'package src\n\n// sr:proves demo/b\nfunc TestB(t *testing.T) {}\n' > src/b_test.go
commit mark-b
run || dump "1: every invariant is implemented and proven, and the range was refused"
passed || dump "1: no passed verdict once demo/b is marked"
COVERED=$(git rev-parse HEAD)

# 2. losing the only proving test
git checkout -q -b lose "$COVERED"; git rm -q src/a_test.go; commit drop-proof
if run; then dump "2: deleting the only test of demo/a passed"; fi
refused "invariant 'demo/a' has no test" || dump "2: no refusal naming demo/a's missing test"

# 3. a marker naming no invariant
git checkout -q -b unknown "$COVERED"
printf 'package src\n\n// sr:invariant demo/zz\nfunc Z() {}\n' > src/z.go; commit unknown
if run; then dump "3: a marker naming no invariant passed"; fi
refused "sr:invariant 'demo/zz' names no spec/demo/invariants/zz.yaml" || dump "3: no refusal naming the missing spec file"

# 4. sr:proves on code
git checkout -q -b misplaced "$COVERED"
printf 'package src\n\n// sr:invariant demo/a\n// sr:proves demo/a\nfunc A() {}\n' > src/a.go; commit misplaced
if run; then dump "4: sr:proves on code passed"; fi
refused "src/a.go: sr:proves belongs on a test" || dump "4: no refusal naming the misplaced sr:proves"

# 5. a long list is cut at 30 lines
git checkout -q -b many "$COVERED"
for i in $(seq 10 29); do inv "n$i"; done
printf 'package src\n\nfunc Helper() {}\n' > src/helper.go; commit many
if run; then dump "5: 20 uncovered invariants passed"; fi
refused "Invariants not implemented or not proven (40)" "invariant 'demo/n10' has no implementation" "... and 10 more." || dump "5: the refusal does not count 40 and cut after 30"
if refused "invariant 'demo/n29' has no test"; then dump "5: the 40th line was shown"; fi
