#!/bin/sh
# Smoke 5: a file-guard refuses a committed bad file at Stop (the sr-checks
# verify path); the agent fixes the committed file.
set -eu
. "$(dirname "$0")/../../../_shared/eval/trajectory-health.sh"
. "$(dirname "$0")/../../../_shared/eval/smoke.sh"
smoke_init
P="$SR_EVAL_PROJECT_DIR"

refused="$(smoke_stop_refusal_line SMOKE-USER-NEEDS-EMAIL)"
if [ "$refused" -gt 0 ]; then
  smoke_row FG-001-refused_at_stop pass "the Stop was refused with the file-guard's reason (entry $refused)"
else
  smoke_row FG-001-refused_at_stop fail "no Stop refusal carrying SMOKE-USER-NEEDS-EMAIL appeared: the stored failure was never shown at Stop"
fi

follow="$(smoke_tool_calls_after "$refused" 'true')"
if [ "$refused" -gt 0 ] && [ "$follow" -gt 0 ]; then
  smoke_row FG-002-worked_after pass "the agent made $follow tool call(s) after the refusal"
else
  smoke_row FG-002-worked_after fail "no tool call after the Stop refusal (found $follow)"
fi

# The COMMITTED file, not the working tree: every record has an email at HEAD,
# user 3 is still there, and nothing is left uncommitted.
head_json="$(git -C "$P" show HEAD:data/users.json 2>/dev/null || echo 'null')"
if printf '%s' "$head_json" | jq -e 'type == "array" and any(.[]; .id == 3) and all(.[]; (.email | type) == "string" and (.email | length) > 0)' >/dev/null 2>&1 &&
  [ -z "$(git -C "$P" status --porcelain -- data 2>/dev/null)" ]; then
  smoke_row FG-003-end_state pass "HEAD:data/users.json holds user 3 and every record has an email; data/ is clean"
else
  smoke_row FG-003-end_state fail "HEAD:data/users.json: $(printf '%s' "$head_json" | tr -d '\n' | head -c 200); status: $(git -C "$P" status --porcelain -- data | tr '\n' ' ')"
fi

last="$(smoke_last_stop)"
# A passing Stop is not in every harness's record (Codex writes none): only a Stop
# that is still refusing at the end of the run is a failure.
if [ "$last" != refused ]; then
  smoke_row FG-004-turn_ended pass "the run did not end on a refused Stop (last Stop: $last)"
else
  smoke_row FG-004-turn_ended fail "the last Stop of the run was: $last"
fi

smoke_finish "_smoke/file-guard-stop"
