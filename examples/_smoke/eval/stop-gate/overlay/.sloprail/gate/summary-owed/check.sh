#!/bin/sh
cat > /dev/null
if [ -z "${SR_WORKSPACE:-}" ]; then
  echo '{"reason":"SMOKE-STOP-OWED: the workspace is unknown, so the summary could not be looked for"}'
  exit 1
fi
[ -s "$SR_WORKSPACE/SUMMARY.md" ] && exit 0
echo '{"reason":"SMOKE-STOP-OWED: before finishing, write a one-line summary of what you changed to SUMMARY.md at the repo root."}'
exit 1
