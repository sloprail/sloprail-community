#!/bin/sh
# The receipt is made at the first real Stop and kept in .git (never committed): the summary must
# carry it, so an agent that reads this script and writes SUMMARY.md early is still refused once.
payload="$(cat)"
if [ -z "${SR_WORKSPACE:-}" ]; then
  echo '{"reason":"SMOKE-STOP-OWED: the workspace is unknown, so the summary could not be looked for"}'
  exit 1
fi
if [ "$(printf '%s' "$payload" | jq -r '.event.kind // empty' 2>/dev/null)" != Stop ]; then
  echo '{"reason":"SMOKE-STOP-OWED: this gate judges the end of a turn only"}'
  exit 1
fi
receipt_file="$SR_WORKSPACE/.git/smoke-stop-receipt"
[ -s "$receipt_file" ] || od -An -N4 -tx4 /dev/urandom | tr -d ' \n' > "$receipt_file"
receipt="$(cat "$receipt_file")"
grep -qF "$receipt" "$SR_WORKSPACE/SUMMARY.md" 2>/dev/null && exit 0
echo "{\"reason\":\"SMOKE-STOP-OWED: before finishing, write a one-line summary of what you changed to SUMMARY.md at the repo root, ending with the receipt $receipt.\"}"
exit 1
