#!/bin/sh
# Smoke 4: a Stop gate blocks the end of the turn once; the agent does the owed work.
set -eu
. "$(dirname "$0")/../../../_shared/eval/trajectory-health.sh"
. "$(dirname "$0")/../../../_shared/eval/smoke.sh"
smoke_init
P="$SR_EVAL_PROJECT_DIR"

refused="$(smoke_stop_refusal_line SMOKE-STOP-OWED)"
if [ "$refused" -gt 0 ]; then
  smoke_row STOP-001-refused pass "the Stop was refused (entry $refused)"
else
  smoke_row STOP-001-refused fail "no Stop refusal carrying SMOKE-STOP-OWED appeared: the Stop hook never blocked the turn"
fi

follow="$(smoke_tool_calls_after "$refused" 'true')"
if [ "$refused" -gt 0 ] && [ "$follow" -gt 0 ]; then
  smoke_row STOP-002-worked_after pass "the agent made $follow tool call(s) after the refusal"
else
  smoke_row STOP-002-worked_after fail "no tool call after the Stop refusal (found $follow): the agent did not act on it"
fi

if [ -s "$P/SUMMARY.md" ] && grep -q 'hello world' "$P/greeting.txt"; then
  smoke_row STOP-003-end_state pass "greeting.txt fixed and SUMMARY.md written"
else
  smoke_row STOP-003-end_state fail "SUMMARY.md written: $([ -s "$P/SUMMARY.md" ] && echo yes || echo no); greeting.txt: $(head -c 80 "$P/greeting.txt")"
fi

last="$(smoke_last_stop)"
# A passing Stop is not in every harness's record (Codex writes none): only a Stop
# that is still refusing at the end of the run is a failure.
if [ "$last" != refused ]; then
  smoke_row STOP-004-turn_ended pass "the run did not end on a refused Stop (last Stop: $last)"
else
  smoke_row STOP-004-turn_ended fail "the last Stop of the run was: $last"
fi

smoke_finish "_smoke/stop-gate"
