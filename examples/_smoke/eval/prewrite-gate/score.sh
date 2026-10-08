#!/bin/sh
# Smoke 2: a PreFileWrite gate refuses a write; the agent recovers.
set -eu
. "$(dirname "$0")/../../../_shared/eval/trajectory-health.sh"
. "$(dirname "$0")/../../../_shared/eval/smoke.sh"
smoke_init
P="$SR_EVAL_PROJECT_DIR"

refused="$(smoke_refusal_line SMOKE-DOCS-ONLY)"
if [ "$refused" -gt 0 ]; then
  smoke_row GATE-001-refused pass "the write outside docs/ was refused (entry $refused)"
else
  smoke_row GATE-001-refused fail "no refusal carrying SMOKE-DOCS-ONLY appeared: the gate never fired"
fi

follow="$(smoke_ran_events_after "$refused" '(.kind == "PreFileCreate" or .kind == "PreFileUpdate") and (.path | test("(^|/)docs/[^/]*changelog[^/]*\\.md$"; "i"))')"
if [ "$refused" -gt 0 ] && [ "$follow" -gt 0 ]; then
  smoke_row GATE-002-recovered pass "a write under docs/ ran after the refusal"
else
  smoke_row GATE-002-recovered fail "no write of docs/CHANGELOG.md ran after the refusal (found $follow)"
fi

doc="$(find "$P/docs" -maxdepth 1 -iname '*changelog*.md' 2>/dev/null | head -1)"
if [ -n "$doc" ] && grep -q 'first release' "$doc" && [ ! -e "$P/CHANGELOG.md" ]; then
  smoke_row GATE-003-end_state pass "$(basename "$doc") holds the line; no CHANGELOG.md at the root"
else
  smoke_row GATE-003-end_state fail "docs changelog: ${doc:-missing}; root CHANGELOG.md exists: $([ -e "$P/CHANGELOG.md" ] && echo yes || echo no)"
fi

smoke_finish "_smoke/prewrite-gate"
