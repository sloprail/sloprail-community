#!/usr/bin/env bash
# Every write or delete of a given file is refused: there is nothing to check.
set -uo pipefail
path="$(jq -r '.event.path // "a given file"')"
jq -n --arg p "$path" '{reason: ("\($p) is given and fixed: the specification, the program tables, the ADRs, CLAUDE.md and the rules are not added to, changed or removed. Change the code or its tests so they meet them as written. If an invariant looks wrong or two contradict each other, leave them as they are and say so in your final message.")}'
exit 1
