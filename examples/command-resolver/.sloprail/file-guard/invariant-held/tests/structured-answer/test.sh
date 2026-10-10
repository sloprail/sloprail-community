#!/usr/bin/env bash
set -euo pipefail
# invariant-held's answer is a table, and post-process.sh decides on it. The spec holds three
# invariants, demo/i01..i03, one bucket (b01); i01 and i02 have marked code and a marked test,
# i03 has neither, so the judge is given i01 and i02.
# 1. every cell passes: the check passes, and the stored verdict carries the table as metadata:
#    the bucket, per invariant its two cells and where its markers are in the judged commit
#    (path and line, found by the script), and the invariant the judge was not shown.
# 2. one failing cell refuses, naming the invariant and the half, with the judge's reasoning
#    after it; the table wins over the judge's own `pass: true`.
# 3. the table wins the other way too: every cell passes under `pass: false`, and the check passes.
# 4. an answer without an entry for an invariant the judge was given is not a verdict: the
#    script exits 65 (a model is asked again; a mock is not asked twice, so the run is an error
#    carrying the script's words), and nothing is stored. An entry for an invariant the judge
#    was not given is turned away the same way.
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
# each step is its own branch off the base with its own edit, so no step is served another's verdict
step() { git checkout -q -b "$1" "$BASE"; printf 'package src\n\n// sr:invariant demo/i02\nfunc F02() { work(); %s() }\n' "$1" > src/f02.go
  git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
metadata() { sr-checks show --json --base "$BASE" --head HEAD | jq -ec '[.[] | select(.kind | contains(":judge:"))] | if length == 1 then .[0].metadata else error("not one judge row") end'; }
unjudged() { local v; v="$(sr-checks verify --json --base "$BASE" --head HEAD 2>/dev/null || true)"; jq -en 'first(inputs) | length > 0 and all(.[]; .status == "missing")' <<<"$v" >/dev/null; }

# 1. a passing table, and its metadata
step pass
echo '{"pass": true, "reasoning": "MOCK all hold", "invariants": {"demo/i01": {"code": "pass", "tests": "pass"}, "demo/i02": {"code": "pass", "tests": "pass"}}}' > "$ANSWER"
run || dump "1: a table in which every cell passes was refused"
want='{"bucket":"b01","invariants":[{"invariant":"demo/i01","code":"pass","tests":"pass","code_at":[{"path":"src/f01.go","line":3},{"path":"src/g01.go","line":5}],"tests_at":[{"path":"src/f01_test.go","line":5}]},{"invariant":"demo/i02","code":"pass","tests":"pass","code_at":[{"path":"src/f02.go","line":3}],"tests_at":[{"path":"src/f02_test.go","line":5}]}],"unjudged":["demo/i03"],"judge_pass":true}'
got="$(metadata)" || dump "1: show --json has no single judge row with metadata"
[ "$(jq -cS . <<<"$got")" = "$(jq -cS . <<<"$want")" ] || dump "1: the stored metadata is not the table with its markers: $got"
sr-checks log --json | jq -es 'any(.[]; .status == "pass" and (.metadata["check[0]:judge:./code-and-tests-hold.md.j2"].bucket == "b01"))' >/dev/null ||
  dump "1: log --json does not carry the metadata under the judge's step"

# 2. a failing cell refuses and names it; the table wins over pass: true
step fail
echo '{"pass": true, "reasoning": "MOCK no test sets the cap to 0", "invariants": {"demo/i01": {"code": "pass", "tests": "pass"}, "demo/i02": {"code": "pass", "tests": "fail"}}}' > "$ANSWER"
if run; then dump "2: a table with a failing cell passed"; fi
jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="invariant-held" and .outcome=="refused"
          and (.reason | contains("Failing: demo/i02 (tests).")) and (.reason | contains("MOCK no test sets the cap to 0")))' "$SR_EVENTS_FILE" >/dev/null ||
  dump "2: the refusal does not name the failing invariant and half with the judge's reasoning"
got="$(metadata)" || dump "2: show --json has no single judge row with metadata"
jq -e '.judge_pass == true and ([.invariants[] | select(.invariant == "demo/i02")][0] | .code == "pass" and .tests == "fail")
       and ([.invariants[] | select(.invariant == "demo/i01")][0] | .code == "pass" and .tests == "pass")' <<<"$got" >/dev/null ||
  dump "2: the stored metadata does not carry the failing cell: $got"

# 3. the table wins over pass: false
step contradicted
echo '{"pass": false, "reasoning": "MOCK says fail, table says pass", "invariants": {"demo/i01": {"code": "pass", "tests": "pass"}, "demo/i02": {"code": "pass", "tests": "pass"}}}' > "$ANSWER"
run || dump "3: a table in which every cell passes was refused because the judge's own pass was false"
got="$(metadata)" || dump "3: show --json has no single judge row with metadata"
jq -e '.judge_pass == false' <<<"$got" >/dev/null || dump "3: the metadata does not keep the judge's own pass: $got"

# 4. a missing entry, and an unknown one, are sent back (exit 65), not judged
step missing
echo '{"pass": true, "reasoning": "", "invariants": {"demo/i01": {"code": "pass", "tests": "pass"}}}' > "$ANSWER"
if run; then dump "4: an answer without demo/i02 passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer without demo/i02 was not rejected as unusable (exit 65)"
grep -q 'no entry for the invariant demo/i02' "$OUT" || dump "4: the rejection does not name the missing invariant"
unjudged || dump "4: a verdict was stored for an answer without demo/i02"
echo '{"pass": true, "reasoning": "", "invariants": {"demo/i01": {"code": "pass", "tests": "pass"}, "demo/i02": {"code": "pass", "tests": "pass"}, "demo/i03": {"code": "pass", "tests": "pass"}}}' > "$ANSWER"
if run; then dump "4: an answer with an invariant the judge was not given passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer with demo/i03 was not rejected as unusable (exit 65)"
grep -q 'demo/i03 is not an invariant you were given' "$OUT" || dump "4: the rejection does not name the unknown invariant"
unjudged || dump "4: a verdict was stored for an answer with an unknown invariant"

# 5. off the schema
echo '{"pass": true, "reasoning": "", "invariants": {"demo/i01": {"code": "pass", "tests": "pass"}, "demo/i02": {"code": "maybe", "tests": "pass"}}}' > "$ANSWER"
if run; then dump "5: a cell that is neither pass nor fail passed"; fi
grep -q "did not match the check's response_schema" "$OUT" || dump "5: the answer was not turned away by the schema"
unjudged || dump "5: a verdict was stored for an answer off the schema"
