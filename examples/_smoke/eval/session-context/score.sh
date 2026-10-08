#!/bin/sh
# Smoke 1: SessionStart context reaches the agent. The only source of the answer
# is the plugin's start-up note (hooks/rules-first.md), which names
# .sloprail/file-guard/structure.yaml.
set -eu
. "$(dirname "$0")/../../../_shared/eval/trajectory-health.sh"
. "$(dirname "$0")/../../../_shared/eval/smoke.sh"
smoke_init

text="$(smoke_final_text)"
case "$text" in
  *.sloprail/file-guard/structure.yaml*)
    smoke_row CTX-001-context_reached pass "the agent named the file the session-start note gives" ;;
  *)
    smoke_row CTX-001-context_reached fail "the agent's last message does not name .sloprail/file-guard/structure.yaml: $(printf '%s' "$text" | head -c 200)" ;;
esac

smoke_finish "_smoke/session-context"
