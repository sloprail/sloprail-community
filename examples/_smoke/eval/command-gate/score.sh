#!/bin/sh
# Smoke 3: a pre-Bash (command) gate refuses; the agent recovers.
set -eu
. "$(dirname "$0")/../../../_shared/eval/trajectory-health.sh"
. "$(dirname "$0")/../../../_shared/eval/smoke.sh"
smoke_init
P="$SR_EVAL_PROJECT_DIR"

refused="$(smoke_refusal_line SMOKE-NO-RM)"
if [ "$refused" -gt 0 ]; then
  smoke_row CMD-001-refused pass "the rm command was refused (entry $refused)"
else
  smoke_row CMD-001-refused fail "no refusal carrying SMOKE-NO-RM appeared: the gate never fired"
fi

# Any way of deleting that ran after the refusal: git rm, or a delete event of
# another route. A command running rm again would have been refused, so it is
# not in the ran events.
follow="$(smoke_ran_events_after "$refused" '.kind == "PreFileDelete" or (.kind == "PreCommandInvoke" and any(.invocations[]?; .bin == "git" and (.argv | index("rm") != null)))')"
if [ "$refused" -gt 0 ] && [ "$follow" -gt 0 ]; then
  smoke_row CMD-002-recovered pass "a deletion that is not rm ran after the refusal"
else
  smoke_row CMD-002-recovered fail "no git rm (or other delete) ran after the refusal (found $follow)"
fi

if [ ! -e "$P/scratch.txt" ] && [ -f "$P/keep.txt" ]; then
  smoke_row CMD-003-end_state pass "scratch.txt is gone, keep.txt is intact"
else
  smoke_row CMD-003-end_state fail "scratch.txt exists: $([ -e "$P/scratch.txt" ] && echo yes || echo no); keep.txt exists: $([ -f "$P/keep.txt" ] && echo yes || echo no)"
fi

smoke_finish "_smoke/command-gate"
