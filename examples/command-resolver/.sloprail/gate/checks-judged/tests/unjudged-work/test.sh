#!/usr/bin/env bash
set -euo pipefail
# checks-judged at Stop: the agent commits code and ends the turn with nothing judged, and the
# Stop is refused with the `sr-checks run` command for exactly the work since the rules; the
# agent runs it and the next Stop passes.
rm -rf .sloprail; git init -q .
mkdir -p .sloprail/gate .sloprail/file-guard/has-package
cp -R "$SR_TEST_SLOPRAIL_DIR/gate/checks-judged" .sloprail/gate/
cp "$SR_TEST_SLOPRAIL_DIR/config.yaml" .sloprail/
rm -rf .sloprail/gate/checks-judged/tests
printf 'match: path endsWith ".go"\nchecks:\n  - script: ./check.sh\n' > .sloprail/file-guard/has-package/file-guard.yaml
printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > .sloprail/file-guard/has-package/check.sh
chmod +x .sloprail/file-guard/has-package/check.sh
git add -A && git -c user.name=t -c user.email=t@t commit -q -m rules
BASE=$(git rev-parse HEAD)
RESULT=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "build it")
HEAD=$(git rev-parse HEAD)
fail() { echo "$1" >&2; echo "$RESULT" | jq -c '.events[]|select(.rule=="checks-judged" or .kind=="FileGuardChecked")|{kind,rule,outcome,reason}' >&2; exit 1; }
[ "$HEAD" != "$BASE" ] || fail "the agent's commit did not land"
stops() { echo "$RESULT" | jq -c '[.events[]|select(.kind=="GateChecked" and .rule=="checks-judged")]'; }
[ "$(stops | jq 'length')" -ge 2 ] || fail "checks-judged did not run at both Stops"
stops | jq -e --arg c "sr-checks run --base $BASE --head $HEAD" '.[0].outcome=="refused" and (.[0].reason|contains($c))' >/dev/null || fail "the first Stop was not refused with the command for the work since the rules"
stops | jq -e '.[-1].outcome!="refused"' >/dev/null || fail "the Stop after the checks ran was still refused"
echo "$RESULT" | jq -e 'any(.events[]; .kind=="FileGuardChecked" and .rule=="has-package")' >/dev/null || fail "the agent's sr-checks run judged nothing"
