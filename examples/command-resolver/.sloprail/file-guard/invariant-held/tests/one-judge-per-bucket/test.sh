#!/usr/bin/env bash
set -euo pipefail
# invariant-held over a committed range. The spec holds 12 invariants, demo/i01..i12: bucket b01 is
# the first ten, b02 the last two. Each has code and a test at the base, except demo/i10 (neither).
# 1. the judge decides both halves: code that does nothing is refused with the judge's reasoning,
#    and so is a test that asserts nothing; the good neighbour of each passes.
# 2. one call per bucket touched: changing code of demo/i02 and a test of demo/i11 is two calls,
#    b01 naming its nine marked invariants (not unmarked demo/i10, not b02's), b02 naming its two.
#    Changing demo/i02 alone is one call, and b02 is not judged again.
# 3. the prompt carries paths, not content: the spec file and the marked files are named, and
#    neither the predicate's text nor the code's is in it.
# 4. an unmarked Go file is not this rule's: no judge call.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard src spec/demo/invariants
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/invariant-held" .sloprail/file-guard/
rm -rf .sloprail/file-guard/invariant-held/tests
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
  printf 'predicate: A {@fld:demo:Thing.on} thing PREDICATETEXT%s holds.\nwhy: w\n' "$i" > "spec/demo/invariants/i$i.yaml"
  [ "$i" = 10 ] && continue
  printf 'package src\n\n// sr:invariant demo/i%s\nfunc F%s() { CODETEXT%s() }\n' "$i" "$i" "$i" > "src/f$i.go"
  printf 'package src\n\n// sr:proves demo/i%s\nfunc Test%s(t *testing.T) { if F%s; false { t.Fatal() } }\n' "$i" "$i" "$i" > "src/f${i}_test.go"
done
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export JUDGE_LOG="$(mktemp)" PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/invariant-held/code-and-tests-hold": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; : > "$JUDGE_LOG"; : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; cat "$JUDGE_LOG" >&2; echo "$1" >&2; exit 1; }
refused() { jq -es --arg w "$1" 'any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-held" and .outcome=="refused" and (.reason|contains($w)))' < "$SR_EVENTS_FILE" >/dev/null; }
passed() { jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-held" and .outcome=="passed") and (any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-held" and .outcome=="refused") | not)' "$SR_EVENTS_FILE" >/dev/null; }
B01="demo/i01 demo/i02 demo/i03 demo/i04 demo/i05 demo/i06 demo/i07 demo/i08 demo/i09 "

# 1. both halves are judged
git checkout -q -b hollow "$BASE"
printf 'package src\n\n// sr:invariant demo/i02\nfunc F02() {}\n' > src/f02.go; commit hollow-code
if run; then dump "1: code that does nothing passed"; fi
refused "MOCK code: src/f02.go does nothing" || dump "1: no refusal carrying the judge's reasoning about the code"
printf 'package src\n\n// sr:invariant demo/i02\nfunc F02() { CODETEXT02(); more() }\n' > src/f02.go; commit real-code
run || dump "1: code that does the work was refused"
passed || dump "1: no passed verdict for the working code"
git checkout -q -b weak "$BASE"
printf 'package src\n\n// sr:proves demo/i03\nfunc Test03(t *testing.T) {}\n' > src/f03_test.go; commit weak-test
if run; then dump "1: a test asserting nothing passed"; fi
refused "MOCK tests: src/f03_test.go asserts nothing" || dump "1: no refusal carrying the judge's reasoning about the test"
printf 'package src\n\n// sr:proves demo/i03\nfunc Test03(t *testing.T) { if F03; true { t.Log() } }\n' > src/f03_test.go; commit real-test
run || dump "1: an asserting test was refused"
passed || dump "1: no passed verdict for the asserting test"

# 2. one call per bucket touched
git checkout -q -b two "$BASE"
printf 'package src\n\n// sr:invariant demo/i02\nfunc F02() { CODETEXT02(); two() }\n' > src/f02.go
printf 'package src\n\n// sr:proves demo/i11\nfunc Test11(t *testing.T) { if F11; true { t.Log() } }\n' > src/f11_test.go
commit two-buckets
run || dump "2: two sound buckets were refused"
[ "$(sort "$JUDGE_LOG" | tr '\n' '|')" = "${B01}|demo/i11 demo/i12 |" ] || dump "2: expected one call for b01 (nine marked invariants) and one for b02, the judge saw: $(tr '\n' '|' < "$JUDGE_LOG")"
printf 'package src\n\n// sr:invariant demo/i02\nfunc F02() { CODETEXT02(); three() }\n' > src/f02.go; commit one-bucket
run || dump "2: the second change to demo/i02 was refused"
[ "$(tr '\n' '|' < "$JUDGE_LOG")" = "${B01}|" ] || dump "2: expected b01 alone to be judged again, the judge saw: $(tr '\n' '|' < "$JUDGE_LOG")"

# 3. paths, not content (the prompt of the b01 call just made)
grep -q '<invariant id="demo/i02" spec="spec/demo/invariants/i02.yaml">' "$PROMPT_LOG" || dump "3: the prompt does not name demo/i02's spec file"
grep -q '<code path="src/f02.go"/>' "$PROMPT_LOG" || dump "3: the prompt does not name the marked code"
grep -q '<test path="src/f02_test.go"/>' "$PROMPT_LOG" || dump "3: the prompt does not name the marked test"
if grep -q 'PREDICATETEXT' "$PROMPT_LOG"; then dump "3: a predicate's text is inlined in the prompt"; fi
if grep -q 'CODETEXT' "$PROMPT_LOG"; then dump "3: the code's text is inlined in the prompt"; fi

# 4. unmarked code is not this rule's
git checkout -q -b unmarked "$BASE"
printf 'package src\n\nfunc Helper() {}\n' > src/helper.go; commit unmarked
run || dump "4: an unmarked file was refused"
[ ! -s "$JUDGE_LOG" ] || dump "4: the judge ran on an unmarked file: $(cat "$JUDGE_LOG")"
