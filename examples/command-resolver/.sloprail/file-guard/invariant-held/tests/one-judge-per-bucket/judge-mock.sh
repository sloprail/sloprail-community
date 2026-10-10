#!/usr/bin/env bash
# Mock judge for invariant-held. Keeps its prompt (appended to PROMPT_LOG) and logs the invariant
# ids it names, one line per judge call. Then answers like the real rubric on one point per half,
# reading the files itself as the rubric says: marked code that is an empty function upholds
# nothing, and a marked test with no `if` asserts nothing. The judge runs in the rule's folder;
# paths are the project's.
# stdin is the rendered prompt, then the check's payload as one JSON line (a mock's extra; a
# model gets the prompt alone). Only the prompt is kept and read.
input="$(grep -v '^{"event":' )"
printf '%s\n' "$input" >> "$PROMPT_LOG"
# One write per call: two buckets are judged at the same time, and two writes would interleave.
printf '%s\n' "$(printf '%s\n' "$input" | grep -o '<invariant id="[^"]*"' | sed 's/.*id="//; s/"$//' | tr '\n' ' ')" >> "$JUDGE_LOG"
root="$(git rev-parse --show-toplevel)"
# The answer is the rule's table (response.schema.json): one entry per invariant named.
cells=""; reason=""; id=""; code=pass; tests=pass
while IFS= read -r line; do
  case "$line" in
    '<invariant id="'*) id="${line#*id=\"}"; id="${id%%\"*}"; code=pass; tests=pass ;;
    '<code path="'*) f="${line#*path=\"}"; f="${f%%\"*}"
      if grep -q '() {}$' "$root/$f"; then code=fail; reason="${reason:-MOCK code: $f does nothing}"; fi ;;
    '<test path="'*) t="${line#*path=\"}"; t="${t%%\"*}"
      if ! grep -q 'if ' "$root/$t"; then tests=fail; reason="${reason:-MOCK tests: $t asserts nothing}"; fi ;;
    '</invariant>') cells="$cells$id"$'\t'"$code"$'\t'"$tests"$'\n' ;;
  esac
done <<<"$input"
printf '%s' "$cells" | jq -Rnc --arg r "$reason" \
  '[inputs | split("\t") | {(.[0]): {code: .[1], tests: .[2]}}] | add // {} | {pass: ($r == ""), reasoning: $r, invariants: .}'
