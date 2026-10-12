#!/usr/bin/env bash
# Mock judge for spec-quality, answering in response.schema.json's shape. Keeps its prompt
# (PROMPT_LOG). It flags every judged invariant whose predicate says "BAD", one finding each.
# With OMIT set it leaves the last judged file out, which post-process.py must reject.
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
bad="$(printf '%s\n' "$input" | awk '/^## The files to judge/{on=1} /^## Related invariants/{on=0} /^## Entities they cite/{on=0} on && /^<file path="/{p=$0} on && p && /BAD/{print p}' | sed 's/.*path="//; s/".*//' | sort -u | tr '\n' ' ')"
out="$(answer "$bad" "MOCK bad")"
if [ -n "${OMIT:-}" ]; then
  out="$(jq -c '.files |= (to_entries | .[:-1] | from_entries)' <<<"$out")"
fi
printf '%s\n' "$out"
