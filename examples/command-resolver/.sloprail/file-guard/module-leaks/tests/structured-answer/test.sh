#!/usr/bin/env bash
set -euo pipefail
# module-leaks over a committed range, and its answer: a list post-process.sh decides on. One
# module, internal/hooks, whose candidates.sh searches for `parseHook(`. Each step adds
# cmd/app/main.go, outside the module's home, with that call on lines 4 and 5: two candidates.
# 0. nothing left, no judge: a new line matching the search inside the module's home, and a
#    file outside it that does not match, are not judged (the mock has no answer to give).
# 1. every candidate a use: the check passes; the judge is named the file listing the two
#    matches, and the stored verdict carries the list as metadata: the module, each candidate's
#    path, line and verdict, and the counts.
# 2. one leak refuses, naming the module and the leak's path and line, with the judge's
#    reasoning after it; the list wins over the judge's own `pass: true`.
# 3. the list wins the other way too: no leak under `pass: false`, and the check passes.
# 4. an answer that leaves a candidate out is not a verdict: the script exits 65 (a model is
#    asked again; a mock is not asked twice, so the run is an error carrying the script's
#    words), and nothing is stored. So is one with a line that was not a candidate, and one
#    calling the same candidate a leak and a use.
# 5. an answer that is not in the schema (a verdict that is neither leak nor use) is no verdict either.
# 6. more candidates than the metadata may hold: the verdict stands, and the list keeps the leaks.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard internal/hooks
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/module-leaks" .sloprail/file-guard/
rm -rf .sloprail/file-guard/module-leaks/tests
printf 'concern: reads what a hook handler printed\nhome: ["internal/hooks/**"]\napi: ["internal/hooks/api.go"]\n' > internal/hooks/module.yaml
printf '#!/usr/bin/env bash\ngit grep -n -F "parseHook(" -- "*.go" || [ $? -eq 1 ]\n' > internal/hooks/candidates.sh
chmod +x internal/hooks/candidates.sh
printf 'package hooks\n\nfunc Parse(b []byte) Result { return parseHook(b) }\n' > internal/hooks/api.go
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
# A refusal is stored as a verdict only for a run that has its session's record (a run without
# one may be missing what a check reads there), so the run is given the session set up above.
export SR_TRANSCRIPT="$(echo "$SETUP" | jq -er .session)"
export ANSWER="$(mktemp)" OUT="$(mktemp)" PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/module-leaks/leak-or-use": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
# each step is its own branch off the base with its own file, so no step is served another's verdict
step() { git checkout -q -b "$1" "$BASE"; mkdir -p cmd/app
  printf 'package main\n\nfunc main() {\n\ta := parseHook(in)\n\tb := parseHook(raw)\n\t%s(a, b)\n}\n' "$1" > cmd/app/main.go; commit "$1"; }
run() { : > "$SR_EVENTS_FILE"; : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; jq -c . "$SR_EVENTS_FILE" >&2; echo "$1" >&2; exit 1; }
metadata() { sr-checks show --json --base "$BASE" --head HEAD | jq -ec '[.[] | select(.kind | contains(":judge:"))] | if length == 1 then .[0].metadata else error("not one judge row") end'; }
unjudged() { local v; v="$(sr-checks verify --json --base "$BASE" --head HEAD 2>/dev/null || true)"; jq -en 'first(inputs) | [.[] | select(.rule == "file-guard/module-leaks")] | length > 0 and all(.[]; .status == "missing")' <<<"$v" >/dev/null; }
answer() { jq -nc --argjson pass "$1" --arg r "$2" --arg four "$3" --arg five "$4" '{pass: $pass, reasoning: $r, candidates: [
  {path: "cmd/app/main.go", line: 4, verdict: $four}, {path: "cmd/app/main.go", line: 5, verdict: $five}]}' > "$ANSWER"; }

# 0. nothing left to judge
echo 'the judge must not be asked' > "$ANSWER"
git checkout -q -b nothing "$BASE"
printf 'package hooks\n\nfunc Again(b []byte) Result { return parseHook(b) }\n' > internal/hooks/again.go
mkdir -p cmd/app; printf 'package main\n\nfunc main() { hooks.Parse(in) }\n' > cmd/app/main.go; commit nothing
run || dump "0: a change with no candidate outside the module's home was refused"
[ ! -s "$PROMPT_LOG" ] || dump "0: the judge was asked with nothing left to judge"

# 1. every candidate a use, and the metadata
step pass
answer true "MOCK both call the API" use use
run || dump "1: a list in which every candidate is a use was refused"
listing="$(grep -o '<module dir="internal/hooks" [^>]*matches="[^"]*"' "$PROMPT_LOG" | sed 's/.*matches="//; s/"$//' || true)"
[ -n "$listing" ] || dump "1: the prompt does not name the module with a file of its matches: $(grep '<module' "$PROMPT_LOG")"
[ "$(cut -d: -f1,2 "$listing" | tr '\n' ' ')" = "cmd/app/main.go:4 cmd/app/main.go:5 " ] || dump "1: the matches file does not list the two candidates: $(cat "$listing")"
want='{"module":"internal/hooks","candidates":[{"path":"cmd/app/main.go","line":4,"verdict":"use"},{"path":"cmd/app/main.go","line":5,"verdict":"use"}],"leaks":0,"uses":2,"judge_pass":true}'
got="$(metadata)" || dump "1: show --json has no single judge row with metadata"
[ "$(jq -cS . <<<"$got")" = "$(jq -cS . <<<"$want")" ] || dump "1: the stored metadata is not the list: $got"
sr-checks log --json | jq -es 'any(.[]; .status == "pass" and (.metadata["check[0]:judge:./leak-or-use.md.j2"].module == "internal/hooks"))' >/dev/null ||
  dump "1: log --json does not carry the metadata under the judge's step"

# 2. a leak refuses and names it; the list wins over pass: true
step leak
answer true "MOCK line 5 parses the handler's output itself: call hooks.Parse" use leak
if run; then dump "2: a list with a leak passed"; fi
jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="module-leaks" and .outcome=="refused"
          and (.reason | contains("Leaks of internal/hooks: cmd/app/main.go:5.")) and (.reason | contains("MOCK line 5 parses the handler")))' "$SR_EVENTS_FILE" >/dev/null ||
  dump "2: the refusal does not name the module and the leak's path and line with the judge's reasoning"
got="$(metadata)" || dump "2: show --json has no single judge row with metadata"
jq -e '.judge_pass == true and .leaks == 1 and .uses == 1 and .module == "internal/hooks"
       and .candidates == [{path: "cmd/app/main.go", line: 4, verdict: "use"}, {path: "cmd/app/main.go", line: 5, verdict: "leak"}]' <<<"$got" >/dev/null ||
  dump "2: the stored metadata does not carry the leak: $got"

# 3. the list wins over pass: false
step contradicted
answer false "MOCK says fail, list says no leak" use use
run || dump "3: a list without a leak was refused because the judge's own pass was false"
got="$(metadata)" || dump "3: show --json has no single judge row with metadata"
jq -e '.judge_pass == false and .leaks == 0' <<<"$got" >/dev/null || dump "3: the metadata does not keep the judge's own pass: $got"

# 4. a candidate left out, a line that was no candidate, and one called both: sent back (exit 65)
step missing
echo '{"pass": true, "reasoning": "", "candidates": [{"path": "cmd/app/main.go", "line": 4, "verdict": "use"}]}' > "$ANSWER"
if run; then dump "4: an answer without cmd/app/main.go:5 passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer without cmd/app/main.go:5 was not rejected as unusable (exit 65)"
grep -q 'no verdict for the match cmd/app/main.go:5' "$OUT" || dump "4: the rejection does not name the missing candidate"
unjudged || dump "4: a verdict was stored for an answer without cmd/app/main.go:5"
echo '{"pass": true, "reasoning": "", "candidates": [{"path": "cmd/app/main.go", "line": 4, "verdict": "use"}, {"path": "cmd/app/main.go", "line": 5, "verdict": "use"}, {"path": "cmd/app/main.go", "line": 6, "verdict": "use"}]}' > "$ANSWER"
if run; then dump "4: an answer with a line that was no candidate passed"; fi
grep -q 'rejected as unusable' "$OUT" || dump "4: the answer with cmd/app/main.go:6 was not rejected as unusable (exit 65)"
grep -q 'cmd/app/main.go:6 is not a match you were given' "$OUT" || dump "4: the rejection does not name the line that was no candidate"
unjudged || dump "4: a verdict was stored for an answer with a line that was no candidate"
echo '{"pass": true, "reasoning": "", "candidates": [{"path": "cmd/app/main.go", "line": 4, "verdict": "use"}, {"path": "cmd/app/main.go", "line": 5, "verdict": "use"}, {"path": "cmd/app/main.go", "line": 5, "verdict": "leak"}]}' > "$ANSWER"
if run; then dump "4: an answer calling one candidate a leak and a use passed"; fi
grep -q 'cmd/app/main.go:5 is called both a leak and a use' "$OUT" || dump "4: the rejection does not name the candidate called both"
unjudged || dump "4: a verdict was stored for an answer calling one candidate a leak and a use"

# 5. off the schema
answer true "" use maybe
if run; then dump "5: a verdict that is neither leak nor use passed"; fi
grep -q "did not match the check's response_schema" "$OUT" || dump "5: the answer was not turned away by the schema"
unjudged || dump "5: a verdict was stored for an answer off the schema"

# 6. more candidates than the metadata may hold
git checkout -q -b many "$BASE"; mkdir -p cmd/app
long="cmd/app/$(printf 'a%.0s' $(seq 1 180)).go"
{ printf 'package main\n\nfunc many() {\n'; for i in $(seq 1 400); do printf '\tparseHook(v%s)\n' "$i"; done; printf '}\n'; } > "$long"; commit many
jq -nc --arg p "$long" '{pass: false, reasoning: "MOCK the first is a leak", candidates: [range(4; 404) | {path: $p, line: ., verdict: (if . == 4 then "leak" else "use" end)}]}' > "$ANSWER"
if run; then dump "6: a list with a leak among 400 candidates passed"; fi
grep -q "Leaks of internal/hooks: $long:4\\." "$OUT" || dump "6: the refusal does not name the leak"
got="$(metadata)" || dump "6: no stored verdict with metadata for 400 candidates"
jq -e --arg p "$long" '.truncated == true and .leaks == 1 and .uses == 399 and .candidates == [{path: $p, line: 4, verdict: "leak"}]' <<<"$got" >/dev/null ||
  dump "6: the metadata of 400 candidates does not keep the leaks and the counts: $(head -c 400 <<<"$got")"
