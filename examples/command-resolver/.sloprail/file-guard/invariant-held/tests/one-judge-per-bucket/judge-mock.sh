#!/usr/bin/env bash
# Mock judge for invariant-held. Keeps its prompt (appended to PROMPT_LOG), logs the invariant
# ids it names (one line per judge call, to JUDGE_LOG) and the batch it was handed (one JSON
# line per call, to BATCH_LOG). Then answers the table of response.schema.json, deciding like
# the real rubric on one point per half, reading the files itself as the rubric says: marked
# code that is an empty function upholds nothing, and a marked test with no `if` asserts
# nothing. The judge runs in the rule's folder; paths are the project's.
# stdin is the rendered prompt, then the check's payload as one JSON line (a mock's extra; a
# model gets the prompt alone).
all="$(cat)"
input="$(printf '%s\n' "$all" | grep -v '^{"event":')"
printf '%s\n' "$input" >> "$PROMPT_LOG"
# One write per log per call: two batches are judged at the same time, and two writes would interleave.
printf '%s\n' "$(printf '%s\n' "$input" | grep -o '<invariant id="[^"]*"' | sed 's/.*id="//; s/"$//' | tr '\n' ' ')" >> "$JUDGE_LOG"
printf '%s\n' "$all" | grep '^{"event":' | jq -c '{batch, subject}' >> "$BATCH_LOG"
root="$(git rev-parse --show-toplevel)"
printf '%s\n' "$input" | awk '
  /<invariant id="/ { match($0, /id="[^"]*"/); id = substr($0, RSTART + 4, RLENGTH - 5); print "I\t" id }
  /<code path="/ { match($0, /path="[^"]*"/); print "C\t" substr($0, RSTART + 6, RLENGTH - 7) }
  /<test path="/ { match($0, /path="[^"]*"/); print "T\t" substr($0, RSTART + 6, RLENGTH - 7) }' |
while IFS=$'\t' read -r k v; do
  case "$k" in
    I) id="$v"; printf '%s\t%s\t%s\t%s\n' I "$id" - - ;;
    C) if grep -q '() {}$' "$root/$v"; then printf '%s\t%s\t%s\t%s\n' C "$id" fail "MOCK code: $v does nothing"; fi ;;
    T) if ! grep -q 'if ' "$root/$v"; then printf '%s\t%s\t%s\t%s\n' T "$id" fail "MOCK tests: $v asserts nothing"; fi ;;
  esac
done | jq -Rnc '[inputs | split("\t")] | reduce .[] as [$k, $id, $s, $why] ({};
    if $k == "I" then .[$id] = {code: "pass", tests: "pass", reasoning: "MOCK \($id) holds"}
    elif $k == "C" then .[$id].code = "fail" | .[$id].reasoning = $why
    else .[$id].tests = "fail" | .[$id].reasoning = $why end)
  | {invariants: .}'
