#!/usr/bin/env bash
# Mock judge for spec-quality. Keeps its prompt (PROMPT_LOG), then decides like the real one on
# one point: two invariants that mention the same field conflict when one empties the value
# after unset and the other keeps it. It sees the conflict only when both stand in its prompt
# (judged, or under "Related invariants"), and refuses only when the pairwise rule is in the
# prompt, so a grouping that splits the pair, or a rubric that lost the rule, fails the case.
input="$(grep -v '^{"event":' )"
printf '%s\n' "$input" >> "$PROMPT_LOG"
if ! printf '%s\n' "$input" | grep -q 'build one input both cover'; then
  echo '{"pass": true, "reasoning": "MOCK: no pairwise rule in the prompt"}'; exit 0
fi
files="$(printf '%s\n' "$input" | awk '/^## The files to judge/{on=1} /^## Entities they cite/{on=0} on')"
if printf '%s\n' "$files" | grep -q 'has the empty string as its' && printf '%s\n' "$files" | grep -q 'keeps the value it had'; then
  echo '{"pass": false, "reasoning": "MOCK conflict: a-unset-empties and z-unset-keeps on Variable.value"}'; exit 0
fi
echo '{"pass": true, "reasoning": ""}'
