#!/usr/bin/env bash
# Mock judge for spec-quality. Keeps its prompt (PROMPT_LOG), then decides like the real one on
# one point: two invariants that mention the same field conflict when one empties the value
# after unset and the other keeps it. It sees the conflict only when both stand in its prompt
# (judged, or under "Related invariants"), and refuses only when the pairwise rule is in the
# prompt, so a grouping that splits the pair, or a rubric that lost the rule, fails the case.
# answer FILES_TO_FLAG MESSAGE: prints the response.schema.json answer, one entry per file under
# "The files to judge" in the prompt ($input), with one finding carrying MESSAGE for each flagged file.
answer() {
  local flagged="$1" msg="$2"
  printf '%s\n' "$input" | awk '/^## The files to judge/{on=1} /^## Related invariants/{on=0} /^## Entities they cite/{on=0} on && /^<file path="/{sub(/.*path="/,""); sub(/".*/,""); print}' |
    jq -Rsc --arg flagged "$flagged" --arg msg "$msg" '
      ($flagged | split(" ") | map(select(length > 0))) as $bad
      | {files: (split("\n") | map(select(length > 0)) | map({key: ., value: {checked: "mock",
          findings: (if (. as $p | $bad | index($p)) then [{rule: "mock", ids: [.], input: $msg, fix: "mock"}] else [] end)}})
        | from_entries)}'
}
input="$(grep -v '^{"event":' )"
printf '%s\n' "$input" >> "$PROMPT_LOG"
if ! printf '%s\n' "$input" | grep -q 'build one input both cover'; then
  answer "" ""; exit 0
fi
files="$(printf '%s\n' "$input" | awk '/^## The files to judge/{on=1} /^## Entities they cite/{on=0} on')"
if printf '%s\n' "$files" | grep -q 'has the empty string as its' && printf '%s\n' "$files" | grep -q 'keeps the value it had'; then
  judged="$(printf '%s\n' "$input" | awk '/^## The files to judge/{on=1} /^## Related invariants/{on=0} /^## Entities they cite/{on=0} on && /^<file path=".*unset-(empties|keeps)/{sub(/.*path="/,""); sub(/".*/,""); print}' | tr '\n' ' ')"
  answer "$judged" "MOCK conflict: a-unset-empties and z-unset-keeps on Variable.value"; exit 0
fi
answer "" ""
