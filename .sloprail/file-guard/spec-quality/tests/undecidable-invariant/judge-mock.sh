#!/usr/bin/env bash
# Mock judge for spec-quality. Keeps its prompt (PROMPT_LOG), then decides like the real one on
# one point of the document-invariant skill: an invariant that asks for the result of reading
# code inside code with no stated bound ("yields the Invocations its text holds" and no depth)
# asks for what no program can decide. It refuses only when the skill's rule on deciding is in
# its prompt, so a skill that no longer reaches the judge fails the case.
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
if ! printf '%s\n' "$input" | grep -q 'an invariant asks only for what a program can decide'; then
  answer "" ""; exit 0
fi
unbounded="$(printf '%s\n' "$input" | awk '
  /^## The files to judge/{on=1} /^## Related invariants/{on=0} /^## Entities they cite/{on=0}
  on && /^<file path="/{p=$0; holds=0; depth=0}
  on && p && /Invocations its text holds/{holds=1}
  on && p && /depth/{depth=1}
  on && p && /^<\/file>/{ if (holds && !depth) print p; p="" }' | sed 's/.*path="//; s/".*//' | sort -u | tr '\n' ' ')"
answer "$unbounded" "MOCK undecidable"
