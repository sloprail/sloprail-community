#!/usr/bin/env bash
# Refuses while `sr-checks verify` over the work since the rules were installed is not clean.
# Plumbing that fails (no git, no sr-checks, no rules commit) lets the turn through: a Stop
# gate that breaks would block every turn.
set -uo pipefail
cat >/dev/null
[ -z "${SR_AGENT_ID:-}" ] || exit 0 # the main session answers for the checks, not a sub-agent
command -v sr-checks >/dev/null 2>&1 || exit 0
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0 # a check starts in its rule's folder
base="$(git log -1 --format=%H -- .sloprail 2>/dev/null)" || exit 0
head="$(git rev-parse HEAD 2>/dev/null)" || exit 0
[ -n "$base" ] && [ "$base" != "$head" ] || exit 0 # nothing committed since the rules
out="$(sr-checks verify --base "$base" --head "$head" 2>&1)" && exit 0
unjudged="$(printf '%s\n' "$out" | grep -c 'not judged yet')"
shown="$(printf '%s\n' "$out" | grep -v 'not judged yet' | awk '!seen[$0]++' | head -40)"
jq -n --arg b "$base" --arg h "$head" --arg n "$unjudged" --arg s "$shown" '{reason: (
  "The committed work is not through the checks yet (\($n) without a verdict). Run\n  sr-checks run --base \($b) --head \($h)\nfix what it refuses, commit, and run it again for the new head until it passes. Run it yourself, in the main session.\n\n" + $s)}'
exit 1
