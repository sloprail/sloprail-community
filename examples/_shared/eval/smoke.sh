#!/bin/sh
# Helpers for the smoke fixtures' score.sh (examples/_smoke/eval/<case>/score.sh).
# Source AFTER trajectory-health.sh, which provides trajectory_entries.
#
# A smoke case is scored on concrete facts of the record, never by a judge:
# the refusal appeared, the follow-up happened after it, and the project ended in
# the right state. Every fact about the record is read from sr-session's
# normalization (`sr-session trajectory normalize`), which puts Claude Code's,
# Codex's and Cursor's records into one shape; nothing here knows which harness
# wrote it. A tool call "ran" by the same normalization's --ran-only: a call a
# hook refused derives no event.
#
#   smoke_init
#   line="$(smoke_refusal_line 'MARKER')"          # entry line of the first refusal, 0 if none
#   smoke_ran_events_after "$line" '<jq predicate on an event>'   # count
#   smoke_row ID pass|fail "reason"                # one scored fact
#   smoke_finish "<subject>"                       # writes the verdict, exits 0 or 1

# smoke_normalize [flags]: the whole session as one JSON array of normalized entries.
# Run with the agent's own HOME: Cursor's record holds no tool results, and sloprail
# keeps them in a store under that HOME and merges them back in when it reads the
# record there. Without it a Cursor call has no result, so no refusal text and no
# "ran" call.
smoke_normalize() {
  HOME="${SR_EVAL_AGENT_HOME:-$HOME}" SLOPRAIL_HARNESS="${SR_EVAL_HARNESS:-claude}" \
    sr-session trajectory normalize --path "$SR_EVAL_TRANSCRIPT" --whole-session "$@" 2>/dev/null |
    jq '[to_entries[] | .value + {line: (.key + 1)}]'
}
# "line" is rewritten to the entry's position in the array: the tool results Cursor's store
# merges in carry a line of 2^30 + their number in the store, which orders against nothing,
# while the array holds the entries in the order they happened on every harness.

# smoke_init reads the record twice into a scratch dir: every entry (all.json) and
# the same with the events of calls that never ran dropped (ran.json).
smoke_init() {
  for v in SR_EVAL_TRANSCRIPT SR_EVAL_BIN_DIR SR_EVAL_PROJECT_DIR; do
    val="$(printenv "$v" || true)"
    if [ -z "$val" ]; then
      echo "$v not set" >&2
      exit 1
    fi
  done
  PATH="$SR_EVAL_BIN_DIR:$PATH"
  export PATH
  SMOKE_DIR="$(mktemp -d)"
  trap 'rm -rf "$SMOKE_DIR"' EXIT
  : > "$SMOKE_DIR/rows"
  smoke_normalize > "$SMOKE_DIR/all.json" || echo '[]' > "$SMOKE_DIR/all.json"
  smoke_normalize --ran-only > "$SMOKE_DIR/ran.json" || echo '[]' > "$SMOKE_DIR/ran.json"
  if ! jq -e 'length > 0' "$SMOKE_DIR/all.json" >/dev/null 2>&1; then
    echo "the record normalized to nothing: $SR_EVAL_TRANSCRIPT" >&2
    exit 1
  fi
}

# The texts a hook delivered to the agent, per entry: a tool result (a refused call's
# reason travels as one), a hook_blocking_error attachment and a refused Stop (the
# Stop hook's own entries). The agent's own prose is not here, so an agent echoing a
# marker does not count as a refusal.
SMOKE_HOOK_TEXTS='
  def text: if type == "string" then . else ([.[]? | .text?] | join(" ")) end;
  def hook_texts:
    [ (.message.content? | arrays | .[] | select(.type == "tool_result") | .content | text),
      (.attachment? // empty | select(.type == "hook_blocking_error") | .blockingError | tostring),
      ((.stopHook? // empty) | select(.refused == true) | tostring) ];'

# smoke_refusal_line MARKER: the entry line of the first hook-delivered text that holds
# MARKER (a tool result, a hook attachment, a refused Stop), 0 when none does.
smoke_refusal_line() {
  jq -r --arg m "$1" "$SMOKE_HOOK_TEXTS"'
    [.[] | select(hook_texts | any(.[]; type == "string" and contains($m))) | .line] | first // 0' "$SMOKE_DIR/all.json"
}

# smoke_stop_refusal_line MARKER: like smoke_refusal_line, but only what the Stop hook
# said: not a tool result, so a command that printed the marker does not count.
# Harnesses differ in how a Stop block is recorded (an attachment, a system entry, a
# follow-up user message), so all three count; the task prompt never holds the marker.
smoke_stop_refusal_line() {
  jq -r --arg m "$1" '
    def stop_texts:
      [ (.attachment? // empty | select(.type == "hook_blocking_error") | .blockingError | tostring),
        ((.stopHook? // empty) | select(.refused == true) | tostring),
        (.message? // empty | select(.role == "user") | .content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) ];
    [.[] | select(.line > 1) | select(stop_texts | any(.[]; type == "string" and contains($m))) | .line] | first // 0' "$SMOKE_DIR/all.json"
}

# smoke_ran_events_after LINE PRED: how many events of calls that RAN, in entries after
# LINE, satisfy the jq predicate (events are PreFileCreate, PreFileUpdate, PreFileDelete
# with .path, PreCommandInvoke with .invocations and .raw).
smoke_ran_events_after() {
  jq -r --argjson l "$1" "[.[] | select(.line > \$l) | .events[]? | select($2)] | length" "$SMOKE_DIR/ran.json"
}

# smoke_tool_calls_after LINE PRED: how many tool calls (ran or not) in entries after LINE
# satisfy the jq predicate on the call block ({name, input}).
smoke_tool_calls_after() {
  jq -r --argjson l "$1" "[.[] | select(.line > \$l) | .message.content? | arrays | .[] | select(.type == \"tool_use\") | select($2)] | length" "$SMOKE_DIR/all.json"
}

# smoke_tool_line PRED: the line of the first entry holding a tool call that satisfies the
# predicate, 0 when none.
smoke_tool_line() {
  jq -r "[.[] | select(.message.content? | arrays | any(.[]; .type == \"tool_use\" and ($1))) | .line] | first // 0" "$SMOKE_DIR/all.json"
}

# smoke_ran_event_line PRED: the line of the first ran event that satisfies the predicate.
smoke_ran_event_line() {
  jq -r "[.[] | select(.events | any(.[]; $1)) | .line] | first // 0" "$SMOKE_DIR/ran.json"
}

# smoke_final_text: the agent's last message that holds prose.
smoke_final_text() {
  jq -r '[.[] | select(.type == "assistant") | .message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end | select(length > 0)] | last // ""' "$SMOKE_DIR/all.json"
}

# smoke_last_stop: refused | passed | none, for the last Stop hook entry the record holds.
smoke_last_stop() {
  jq -r '[.[] | select(.stopHook != null)] | last | if . == null then "none" elif .stopHook.refused then "refused" else "passed" end' "$SMOKE_DIR/all.json"
}

# smoke_row ID STATUS REASON: one scored fact; STATUS is pass, fail or info (not gating).
smoke_row() {
  jq -cn --arg id "$1" --arg s "$2" --arg r "$3" '{check_id: $id, status: $s, reasoning: $r}' >> "$SMOKE_DIR/rows"
}

# smoke_finish SUBJECT: writes the verdict (every row), says each failure on stdout (the
# reason sr-eval shows), and exits 1 when any row failed.
smoke_finish() {
  overall=pass
  if jq -e -s 'any(.[]; .status == "fail")' "$SMOKE_DIR/rows" >/dev/null; then overall=fail; fi
  if [ -n "${SR_EVAL_VERDICT_OUT:-}" ]; then
    jq -s --arg subject "$1" --arg status "$overall" '{subject: $subject, status: $status, rows: .}' "$SMOKE_DIR/rows" > "$SR_EVAL_VERDICT_OUT"
  fi
  jq -r -s '.[] | (.status | ascii_upcase) + " " + .check_id + ": " + .reasoning' "$SMOKE_DIR/rows" >&2
  if [ "$overall" = fail ]; then
    jq -r -s '[.[] | select(.status == "fail") | .check_id + ": " + .reasoning] | join("; ")' "$SMOKE_DIR/rows"
    exit 1
  fi
  exit 0
}
