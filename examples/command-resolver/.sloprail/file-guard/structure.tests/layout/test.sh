#!/usr/bin/env bash
set -euo pipefail
# The resolver's layout (adr/file-placement). Permitted: the entry point under cmd/, code, a test
# and a module.yaml under internal/, a nested package, go.mod. Refused, each beside a permitted
# neighbour: pkg/, a Go file at the root, scripts/, a data file under internal/ that is not a
# case file, an upper-case directory, docs/. Also permitted: a case file (testdata/*.jsonl)
# beside a test, and an end-to-end test and its case file under tests/<feature>/. Refused there:
# a non-test Go file, a test directly under tests/, and a testdata/ at the root.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/file-guard
cp "$SR_TEST_SLOPRAIL_DIR/file-guard/structure.yaml" .sloprail/file-guard/
git add -A && git -c user.name=t -c user.email=t@t commit -q -m setup
RESULT=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "build it")
fail() { echo "$1" >&2; echo "$RESULT" | jq -c '[.events[]|select(.kind=="StructureChecked")|{id: .tool_use_id, o: .outcome}]' >&2; exit 1; }
outcome() { echo "$RESULT" | jq -e --arg id "$1" --arg o "$2" '[.events[]|select(.kind=="StructureChecked" and .rule=="structure" and .tool_use_id==$id)] | length==1 and .[0].outcome==$o' >/dev/null; }
for id in ok-cmd ok-code ok-test ok-module ok-nested ok-gomod ok-cases ok-e2e ok-e2e-cases; do outcome "$id" permitted || fail "$id was not permitted"; done
for id in no-pkg no-root no-script no-testdata no-case no-doc no-e2e-helper no-e2e-root no-root-testdata; do outcome "$id" refused || fail "$id was not refused"; done
echo "$RESULT" | jq -e '[.events[]|select(.kind=="StructureChecked" and .rule=="structure" and .outcome=="refused")] | all(.reason|contains("matches no `allow` entry"))' >/dev/null || fail "a refusal is not the structure's"
test -f cmd/resolve/main.go && test -f internal/words/quote/quote.go && test -f internal/words/module.yaml
test ! -e pkg && test ! -e main.go && test ! -e scripts && test ! -e internal/words/testdata/cases.json && test ! -e internal/Words && test ! -e docs
test -f internal/words/testdata/quoting.jsonl && test -f tests/command-strings/bash_c_test.go && test ! -e tests/words/helper.go && test ! -e tests/all_test.go && test ! -e testdata
