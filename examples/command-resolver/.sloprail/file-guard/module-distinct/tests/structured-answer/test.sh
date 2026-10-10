#!/usr/bin/env bash
set -euo pipefail
# module-distinct's answer is a table, and post-process.sh decides on it. Three modules at the
# base: internal/a, internal/b, internal/c. Each step changes a and b, so the judge is asked to
# judge those two, against c.
# 1. every cell passes: the check passes, and the stored verdict carries the table as metadata:
#    per judged module its two cells, and the module shown but not judged.
# 2. one failing cell refuses, naming the module and the cell, with the judge's reasoning after
#    it; the table wins over the judge's own `pass: true`.
# 3. the table wins the other way too: every cell passes under `pass: false`, and the check passes.
# 4. an answer without an entry for a changed module is not a verdict: the script exits 65 (a
#    model is asked again; a mock is not asked twice, so the run is an error carrying the
#    script's words), and nothing is stored. An entry for a module that is not changed, or that
#    does not exist, is turned away the same way.
# 5. an answer that is not in the schema (a cell that is neither pass nor fail) is no verdict either.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/module-distinct" .sloprail/file-guard/
rm -rf .sloprail/file-guard/module-distinct/tests
for m in a b c; do
  mkdir -p "internal/$m"
  printf 'concern: owns thing %s\nhome: ["internal/%s/**"]\napi: ["internal/%s/api.go"]\n' "$m" "$m" "$m" > "internal/$m/module.yaml"
  printf 'package %s\n\nfunc Api() {}\n' "$m" > "internal/$m/api.go"
done
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
# A refusal is stored as a verdict only for a run that has its session's record (a run without
# one may be missing what a check reads there), so the run is given the session set up above.
export SR_TRANSCRIPT="$(echo "$SETUP" | jq -er .session)"
export ANSWER="$(mktemp)" OUT="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/module-distinct/distinct-concern": $p}')
# each step is its own branch off the base with its own concerns, so no step is served another's verdict
step() { git checkout -q -b "$1" "$BASE"
  for m in a b; do printf 'concern: owns thing %s, %s\nhome: ["internal/%s/**"]\napi: ["internal/%s/api.go"]\n' "$m" "$1" "$m" "$m" > "internal/$m/module.yaml"; done
  git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
metadata() { sr-checks show --json --base "$BASE" --head HEAD | jq -ec '[.[] | select(.kind | contains(":judge:"))] | if length == 1 then .[0].metadata else error("not one judge row") end'; }
unjudged() { local v; v="$(sr-checks verify --json --base "$BASE" --head HEAD 2>/dev/null || true)"; jq -en 'first(inputs) | length > 0 and all(.[]; .status == "missing")' <<<"$v" >/dev/null; }

# 1. a passing table, and its metadata
step pass
echo '{"pass": true, "reasoning": "MOCK all distinct", "modules": {"internal/a": {"concern": "pass", "home": "pass"}, "internal/b": {"concern": "pass", "home": "pass"}}}' > "$ANSWER"
run || dump "1: a table in which every cell passes was refused"
want='{"modules":[{"module":"internal/a","concern":"pass","home":"pass"},{"module":"internal/b","concern":"pass","home":"pass"}],"unjudged":["internal/c"],"judge_pass":true}'
got="$(metadata)" || dump "1: show --json has no single judge row with metadata"
[ "$(jq -cS . <<<"$got")" = "$(jq -cS . <<<"$want")" ] || dump "1: the stored metadata is not the table: $got"
sr-checks log --json | jq -es 'any(.[]; .status == "pass" and (.metadata["check[0]:judge:./distinct-concern.md.j2"].modules | length == 2))' >/dev/null ||
  dump "1: log --json does not carry the metadata under the judge's step"

# 2. a failing cell refuses and names it; the table wins over pass: true
step fail
echo '{"pass": true, "reasoning": "MOCK internal/b/** claims files of thing c", "modules": {"internal/a": {"concern": "pass", "home": "pass"}, "internal/b": {"concern": "pass", "home": "fail"}}}' > "$ANSWER"
if run; then dump "2: a table with a failing cell passed"; fi
jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="module-distinct" and .outcome=="refused"
          and (.reason | contains("Failing: internal/b (home).")) and (.reason | contains("MOCK internal/b/** claims files of thing c")))' "$SR_EVENTS_FILE" >/dev/null ||
  dump "2: the refusal does not name the failing module and cell with the judge's reasoning"
got="$(metadata)" || dump "2: show --json has no single judge row with metadata"
jq -e '.judge_pass == true and ([.modules[] | select(.module == "internal/b")][0] | .concern == "pass" and .home == "fail")
       and ([.modules[] | select(.module == "internal/a")][0] | .concern == "pass" and .home == "pass")' <<<"$got" >/dev/null ||
  dump "2: the stored metadata does not carry the failing cell: $got"

# 3. the table wins over pass: false
step contradicted
echo '{"pass": false, "reasoning": "MOCK says fail, table says pass", "modules": {"internal/a": {"concern": "pass", "home": "pass"}, "internal/b": {"concern": "pass", "home": "pass"}}}' > "$ANSWER"
run || dump "3: a table in which every cell passes was refused because the judge's own pass was false"
got="$(metadata)" || dump "3: show --json has no single judge row with metadata"
jq -e '.judge_pass == false' <<<"$got" >/dev/null || dump "3: the metadata does not keep the judge's own pass: $got"

# 4. a missing entry, and one that is not asked for, are sent back (exit 65), not judged
step missing
echo '{"pass": true, "reasoning": "", "modules": {"internal/a": {"concern": "pass", "home": "pass"}}}' > "$ANSWER"
if run; then dump "4: an answer without internal/b passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer without internal/b was not rejected as unusable (exit 65)"
grep -q 'no entry for the module internal/b' "$OUT" || dump "4: the rejection does not name the missing module"
unjudged || dump "4: a verdict was stored for an answer without internal/b"
for other in internal/c internal/zzz; do
  jq -nc --arg o "$other" '{pass: true, reasoning: "", modules: ({"internal/a": {concern: "pass", home: "pass"}, "internal/b": {concern: "pass", home: "pass"}} + {($o): {concern: "pass", home: "pass"}})}' > "$ANSWER"
  if run; then dump "4: an answer with an entry for $other passed"; fi
  grep -q 'rejected as unusable' "$OUT" || dump "4: the answer with $other was not rejected as unusable (exit 65)"
  grep -q "$other is not a module marked changed" "$OUT" || dump "4: the rejection does not name $other"
  unjudged || dump "4: a verdict was stored for an answer with an entry for $other"
done

# 5. off the schema
echo '{"pass": true, "reasoning": "", "modules": {"internal/a": {"concern": "pass", "home": "pass"}, "internal/b": {"concern": "maybe", "home": "pass"}}}' > "$ANSWER"
if run; then dump "5: a cell that is neither pass nor fail passed"; fi
grep -q "did not match the check's response_schema" "$OUT" || dump "5: the answer was not turned away by the schema"
unjudged || dump "5: a verdict was stored for an answer off the schema"
