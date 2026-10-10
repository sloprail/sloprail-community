#!/usr/bin/env bash
set -euo pipefail
# module-distinct over a committed range. Three modules at the base: internal/a, internal/b, internal/c.
# 1. one call for the changeset, whatever the number of modules it changes: changing a's concern
#    is one call that names all three modules, a as changed and b, c as not; changing a and b
#    together is still one call, naming both as changed.
# 2. the prompt carries paths, not content: each home names a file listing what it matches, and
#    no code text is in the prompt.
# 3. the judge's refusal reaches the agent: a new module whose concern repeats another's is refused
#    with the judge's reasoning.
# 4. a file landing in a changed module's home judges the modules again; the same range again does not.
# 5. a changeset that touches no module.yaml is not this rule's: no judge call.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard
cp -R "$SR_TEST_SLOPRAIL_DIR/_lib" .sloprail/
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/module-distinct" .sloprail/file-guard/
rm -rf .sloprail/file-guard/module-distinct/tests
for m in a b c; do
  mkdir -p "internal/$m"
  printf 'concern: owns thing %s\nhome: ["internal/%s/**"]\napi: ["internal/%s/api.go"]\n' "$m" "$m" "$m" > "internal/$m/module.yaml"
  printf 'package %s\n\nfunc CODETEXT%s() {}\n' "$m" "$m" > "internal/$m/api.go"
done
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export JUDGE_LOG="$(mktemp)" PROMPT_LOG="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.sh" '{"file-guard/module-distinct/distinct-concern": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$SR_EVENTS_FILE"; : > "$JUDGE_LOG"; : > "$PROMPT_LOG"; sr-checks run --base "$BASE" --head HEAD >/dev/null 2>&1; }
dump() { jq -c . "$SR_EVENTS_FILE" >&2; cat "$JUDGE_LOG" >&2; echo "$1" >&2; exit 1; }
calls() { tr '\n' '|' < "$JUDGE_LOG"; }

# 1. one call per changeset
git checkout -q -b one "$BASE"
printf 'concern: owns thing a, restated\nhome: ["internal/a/**"]\napi: ["internal/a/api.go"]\n' > internal/a/module.yaml; commit one-module
run || dump "1: a sound change to one module was refused"
[ "$(calls)" = "internal/a=true internal/b=false internal/c=false |" ] || dump "1: expected one call naming all three modules with a changed, the judge saw: $(calls)"
# 2. paths, not content (the prompt of the call just made)
grep -q '<home glob="internal/a/\*\*" files="[^"]*" count="2"/>' "$PROMPT_LOG" || dump "2: a's home does not name a file listing its two files: $(grep '<home' "$PROMPT_LOG" | head -3)"
listing="$(grep -o '<home glob="internal/a/\*\*" files="[^"]*"' "$PROMPT_LOG" | sed 's/.*files="//; s/"$//')"
grep -qx 'internal/a/api.go' "$listing" || dump "2: the listing of a's home does not hold internal/a/api.go"
if grep -q 'CODETEXT' "$PROMPT_LOG"; then dump "2: code text is inlined in the prompt"; fi
git checkout -q -b two "$BASE"
printf 'concern: owns thing a, restated\nhome: ["internal/a/**"]\napi: ["internal/a/api.go"]\n' > internal/a/module.yaml
printf 'concern: owns thing b, restated\nhome: ["internal/b/**"]\napi: ["internal/b/api.go"]\n' > internal/b/module.yaml; commit two-modules
run || dump "1: a sound change to two modules was refused"
[ "$(calls)" = "internal/a=true internal/b=true internal/c=false |" ] || dump "1: expected ONE call with a and b changed, the judge saw: $(calls)"

# 3. the judge's refusal reaches the agent
git checkout -q -b dup "$BASE"
mkdir -p internal/d
printf 'concern: DUPLICATE of thing a\nhome: ["internal/d/**"]\napi: []\n' > internal/d/module.yaml; commit duplicate
if run; then dump "3: a module repeating another's concern passed"; fi
jq -es 'any(.[]; .kind=="FileGuardChecked" and .rule=="module-distinct" and .outcome=="refused" and (.reason|contains("MOCK: internal/d repeats another concern")))' < "$SR_EVENTS_FILE" >/dev/null ||
  dump "3: no refusal carrying the judge's reasoning"

# 4. a file landing in a home judges again; the same range again does not
git checkout -q one
run; [ ! -s "$JUDGE_LOG" ] || dump "4: an unchanged range was judged again: $(calls)"
printf 'package a\n\nfunc More() {}\n' > internal/a/more.go; commit lands-in-home
run || dump "4: a file landing in a's home was refused"
[ "$(calls)" = "internal/a=true internal/b=false internal/c=false |" ] || dump "4: expected the modules to be judged again in one call, the judge saw: $(calls)"

# 5. no module.yaml in the changeset
git checkout -q -b code-only "$BASE"
printf 'package b\n\nfunc Other() {}\n' > internal/b/other.go; commit code-only
run || dump "5: a changeset with no module.yaml was refused"
[ ! -s "$JUDGE_LOG" ] || dump "5: the judge ran with no module.yaml changed: $(calls)"
