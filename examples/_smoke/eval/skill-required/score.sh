#!/bin/sh
# Smoke 7: a skill-required gate refuses, the skill is read, the write then passes.
set -eu
. "$(dirname "$0")/../../../_shared/eval/trajectory-health.sh"
. "$(dirname "$0")/../../../_shared/eval/smoke.sh"
smoke_init
P="$SR_EVAL_PROJECT_DIR"

refused="$(smoke_refusal_line needs-guardrails-skill)"
if [ "$refused" -gt 0 ]; then
  smoke_row SKILL-001-refused pass "the write was refused until the skill was read (entry $refused)"
else
  smoke_row SKILL-001-refused fail "no refusal naming needs-guardrails-skill appeared: the gate never fired"
fi

# The read, whichever way the harness does it: a Skill call, or any tool call (a
# Read, a cat) whose input names the skill's SKILL.md or its name.
read_pred='((.input | tostring) | test("authoring-guardrails"))'
read_line="$(smoke_tool_line "$read_pred and .input != null")"
after="$(smoke_tool_calls_after "$refused" "$read_pred")"
if [ "$refused" -gt 0 ] && [ "$after" -gt 0 ]; then
  smoke_row SKILL-002-skill_read pass "the skill was read after the refusal (first mention at entry $read_line)"
else
  smoke_row SKILL-002-skill_read fail "no call naming authoring-guardrails after the refusal (found $after)"
fi

first_read_after="$(jq -r --argjson l "$refused" --arg p 'authoring-guardrails' '[.[] | select(.line > $l) | select(.message.content? | arrays | any(.[]; .type == "tool_use" and ((.input | tostring) | contains($p)))) | .line] | first // 0' "$SMOKE_DIR/all.json")"
landed="$(smoke_ran_events_after "$first_read_after" '(.kind == "PreFileCreate" or .kind == "PreFileUpdate") and (.path | test("(^|/)memories/idea\\.md$"))')"
if [ "$first_read_after" -gt 0 ] && [ "$landed" -gt 0 ]; then
  smoke_row SKILL-003-write_after_read pass "memories/idea.md was written after the skill was read"
else
  smoke_row SKILL-003-write_after_read fail "no write of memories/idea.md ran after the skill read (read at $first_read_after, writes after: $landed)"
fi

if [ -f "$P/memories/idea.md" ] && grep -q '^# an idea' "$P/memories/idea.md"; then
  smoke_row SKILL-004-end_state pass "memories/idea.md holds the line"
else
  smoke_row SKILL-004-end_state fail "memories/idea.md: $(head -c 100 "$P/memories/idea.md" 2>/dev/null || echo missing)"
fi

smoke_finish "_smoke/skill-required"
