#!/usr/bin/env bash
set -euo pipefail
# givens-frozen refuses a write to every kind of given file (an existing invariant, a new one, an
# ADR, the program tables, CLAUDE.md, a rule) and the delete of an invariant, each with a reason
# naming the path; and leaves the neighbours alone: a code file and README.md are not its business.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/gate spec/words/invariants adr/file-size config
cp -R "$SR_TEST_SLOPRAIL_DIR/gate/givens-frozen" .sloprail/gate/
rm -rf .sloprail/gate/givens-frozen/tests
printf 'predicate: original\n' > spec/words/invariants/a.yaml
printf 'limits: {go: 150}\n' > adr/file-size/ADR.md
printf 'wrappers: [sudo]\n' > config/builtin.yaml
printf 'the conventions\n' > CLAUDE.md
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
RESULT=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "build it")
fail() { echo "$1" >&2; echo "$RESULT" | jq -c '.events[]|select(.rule=="givens-frozen")|{kind,outcome,tool_use_id,reason}' >&2; exit 1; }
refused() { echo "$RESULT" | jq -e --arg id "$1" --arg p "$2" '[.events[]|select(.kind=="GateChecked" and .rule=="givens-frozen" and .tool_use_id==$id)] | length>=1 and all(.outcome=="refused") and any(.reason|contains($p + " is given and fixed"))' >/dev/null; }
untouched() { echo "$RESULT" | jq -e --arg id "$1" '[.events[]|select(.rule=="givens-frozen" and .tool_use_id==$id)] | length==0' >/dev/null; }
refused w-spec spec/words/invariants/a.yaml || fail "rewriting an invariant was not refused"
refused w-new spec/words/invariants/new.yaml || fail "adding an invariant was not refused"
refused w-adr adr/file-size/ADR.md || fail "rewriting an ADR was not refused"
refused w-config config/builtin.yaml || fail "rewriting the program tables was not refused"
refused w-claude CLAUDE.md || fail "rewriting CLAUDE.md was not refused"
refused w-rule .sloprail/gate/givens-frozen/gate.yaml || fail "rewriting a rule was not refused"
refused d-spec spec/words/invariants/a.yaml || fail "deleting an invariant was not refused"
untouched w-code || fail "a code file was judged"
untouched w-readme || fail "README.md was judged"
[ "$(cat spec/words/invariants/a.yaml)" = "predicate: original" ] || fail "the invariant changed on disk"
test ! -e spec/words/invariants/new.yaml || fail "the new invariant landed"
[ "$(cat adr/file-size/ADR.md)" = "limits: {go: 150}" ] || fail "the ADR changed on disk"
[ "$(cat CLAUDE.md)" = "the conventions" ] || fail "CLAUDE.md changed on disk"
test -f internal/words/a.go || fail "the code file was not written"
test -f README.md || fail "README.md was not written"
