#!/usr/bin/env bash
set -euo pipefail
# invariant-held's judge answers a table for its batch, and post-process.sh turns each row into
# that invariant's verdict. The spec holds three invariants, demo/i01..i03, one bucket (b01);
# demo/i01 and demo/i02 have marked code and a marked test, demo/i03 has neither. Each step
# changes all three, so the batch b01 holds all three subjects and the judge is given i01 and i02.
# 1. every cell passes: each invariant passes, and each stored verdict carries its own row as
#    metadata: the bucket, its two cells and where its markers are in the judged commit (path and
#    line, found by the script). demo/i03 passes unjudged, its metadata saying so.
# 2. one failing cell refuses that invariant alone, naming the half, with its own reasoning
#    and not its neighbour's; demo/i01 still passes.
# 3. an entry for demo/i03, which the judge was not given but is in its batch, is ignored.
# 4. an answer without an entry for an invariant the judge was given is not a verdict: the
#    script exits 65 (a model is asked again; a mock is not asked twice, so the run is an error
#    carrying the script's words), and nothing is stored for any invariant of the batch. An
#    entry for an invariant outside the batch is turned away the same way.
# 5. an answer that is not in the schema (a cell that is neither pass nor fail) is no verdict either.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard src spec/demo/invariants
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/invariant-held" .sloprail/file-guard/
rm -rf .sloprail/file-guard/invariant-held/tests
for i in 01 02 03; do
  printf 'predicate: A thing %s holds.\nwhy: w\n' "$i" > "spec/demo/invariants/i$i.yaml"
  [ "$i" = 03 ] && continue
  printf 'package src\n\n// sr:invariant demo/i%s\nfunc F%s() { work() }\n' "$i" "$i" > "src/f$i.go"
  printf 'package src\n\nimport "testing"\n\n// sr:proves demo/i%s\nfunc Test%s(t *testing.T) { if F%s; false { t.Fatal() } }\n' "$i" "$i" "$i" > "src/f${i}_test.go"
done
# a second marker for demo/i01, in another file
printf 'package src\n\nfunc other() {}\n\n// sr:invariant demo/i01\nfunc G01() { work() }\n' > src/g01.go
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
# A refusal is stored as a verdict only for a run that has its session's record (a run without
# one may be missing what a check reads there), so the run is given the session set up above.
export SR_TRANSCRIPT="$(echo "$SETUP" | jq -er .session)"
export ANSWER="$(mktemp)" OUT="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/invariant-held/code-and-tests-hold": $p}')
# each step is its own branch off the base, touching all three invariants with its own edit,
# so no step is served another's verdict
step() { git checkout -q -b "$1" "$BASE"
  printf 'package src\n\n// sr:invariant demo/i01\nfunc F01() { work(); %s() }\n' "$1" > src/f01.go
  printf 'package src\n\n// sr:invariant demo/i02\nfunc F02() { work(); %s() }\n' "$1" > src/f02.go
  printf 'predicate: A thing 03 holds (%s).\nwhy: w\n' "$1" > spec/demo/invariants/i03.yaml
  git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
# row SUBJECT — the judge row of `show --json` for SUBJECT
row() { sr-checks show --json --base "$BASE" --head HEAD | jq -ec --arg s "$1" '[.[] | select(.rule == "file-guard/invariant-held" and .subject == $s and (.kind | contains(":judge:")))]
  | if length == 1 then .[0] else error("not one judge row for \($s)") end'; }
unjudged() { local v; v="$(sr-checks verify --json --base "$BASE" --head HEAD 2>/dev/null || true)"; jq -en 'first(inputs) | length > 0 and all(.[]; .status == "missing")' <<<"$v" >/dev/null; }
I01='"demo/i01": {"code": "pass", "tests": "pass", "reasoning": "MOCK i01 holds"}'

# 1. a passing table: one verdict per invariant, each with its own row
step pass
echo "{\"invariants\": {$I01, \"demo/i02\": {\"code\": \"pass\", \"tests\": \"pass\", \"reasoning\": \"MOCK i02 holds\"}}}" > "$ANSWER"
run || dump "1: a table in which every cell passes was refused"
got="$(row demo/i01)" || dump "1: show --json has no single judge row for demo/i01"
want='{"bucket":"b01","invariant":"demo/i01","code":"pass","tests":"pass","code_at":[{"path":"src/f01.go","line":3},{"path":"src/g01.go","line":5}],"tests_at":[{"path":"src/f01_test.go","line":5}]}'
[ "$(jq -cS '.metadata' <<<"$got")" = "$(jq -cS . <<<"$want")" ] || dump "1: demo/i01's stored metadata is not its row with its markers: $got"
jq -e '.status == "pass" and .batch == "b01"' <<<"$got" >/dev/null || dump "1: demo/i01 has no passing row in batch b01: $got"
got="$(row demo/i02)" || dump "1: show --json has no single judge row for demo/i02"
jq -e '.status == "pass" and .metadata.invariant == "demo/i02" and .metadata.code_at == [{"path":"src/f02.go","line":3}]' <<<"$got" >/dev/null ||
  dump "1: demo/i02's row is not its own: $got"
got="$(row demo/i03)" || dump "1: show --json has no single judge row for demo/i03"
jq -e '.status == "pass" and .metadata == {"bucket":"b01","invariant":"demo/i03","unjudged":true}' <<<"$got" >/dev/null ||
  dump "1: demo/i03 did not pass unjudged: $got"

# 2. a failing cell refuses its invariant alone, with its own reasoning
step fail
echo "{\"invariants\": {$I01, \"demo/i02\": {\"code\": \"pass\", \"tests\": \"fail\", \"reasoning\": \"MOCK no test sets the cap to 0\"}}}" > "$ANSWER"
if run; then dump "2: a table with a failing cell passed"; fi
jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-held" and .outcome=="refused"
          and (.reason | contains("Failing: tests.")) and (.reason | contains("MOCK no test sets the cap to 0"))
          and (.reason | contains("MOCK i01 holds") | not))' "$SR_EVENTS_FILE" >/dev/null ||
  dump "2: the refusal does not name the failing half with demo/i02's own reasoning alone"
got="$(row demo/i02)" || dump "2: show --json has no single judge row for demo/i02"
jq -e '.status == "fail" and .metadata.code == "pass" and .metadata.tests == "fail"' <<<"$got" >/dev/null || dump "2: demo/i02's row does not carry the failing cell: $got"
got="$(row demo/i01)" || dump "2: show --json has no single judge row for demo/i01"
jq -e '.status == "pass"' <<<"$got" >/dev/null || dump "2: demo/i01 did not pass beside its failing neighbour: $got"

# 3. an entry for an unmarked invariant of the batch is ignored
step extra
echo "{\"invariants\": {$I01, \"demo/i02\": {\"code\": \"pass\", \"tests\": \"pass\", \"reasoning\": \"\"}, \"demo/i03\": {\"code\": \"fail\", \"tests\": \"fail\", \"reasoning\": \"MOCK\"}}}" > "$ANSWER"
run || dump "3: an answer with an entry for the unmarked demo/i03 was refused"
got="$(row demo/i03)" || dump "3: show --json has no single judge row for demo/i03"
jq -e '.status == "pass" and .metadata.unjudged == true' <<<"$got" >/dev/null || dump "3: demo/i03 was judged by the entry it was not given: $got"

# 4. a missing entry, and one outside the batch, are sent back (exit 65), not judged
step missing
echo "{\"invariants\": {$I01}}" > "$ANSWER"
if run; then dump "4: an answer without demo/i02 passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer without demo/i02 was not rejected as unusable (exit 65)"
grep -q 'no entry for the invariant demo/i02' "$OUT" || dump "4: the rejection does not name the missing invariant"
unjudged || dump "4: a verdict was stored for an answer without demo/i02"
echo "{\"invariants\": {$I01, \"demo/i02\": {\"code\": \"pass\", \"tests\": \"pass\", \"reasoning\": \"\"}, \"demo/i09\": {\"code\": \"pass\", \"tests\": \"pass\", \"reasoning\": \"\"}}}" > "$ANSWER"
if run; then dump "4: an answer with an invariant outside the batch passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer with demo/i09 was not rejected as unusable (exit 65)"
grep -q 'demo/i09 is not an invariant you were given' "$OUT" || dump "4: the rejection does not name the unknown invariant"
unjudged || dump "4: a verdict was stored for an answer with an unknown invariant"

# 5. off the schema
echo "{\"invariants\": {$I01, \"demo/i02\": {\"code\": \"maybe\", \"tests\": \"pass\", \"reasoning\": \"\"}}}" > "$ANSWER"
if run; then dump "5: a cell that is neither pass nor fail passed"; fi
grep -q "did not match the check's response_schema" "$OUT" || dump "5: the answer was not turned away by the schema"
unjudged || dump "5: a verdict was stored for an answer off the schema"
