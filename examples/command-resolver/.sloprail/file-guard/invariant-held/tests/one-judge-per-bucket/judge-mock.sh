#!/usr/bin/env bash
# Mock judge for invariant-held. Keeps its prompt (appended to PROMPT_LOG) and logs the invariant
# ids it names, one line per judge call. Then decides like the real rubric on one point per half,
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
for f in $(printf '%s\n' "$input" | grep -o '<code path="[^"]*"' | sed 's/.*path="//; s/"$//'); do
  if grep -q '() {}$' "$root/$f"; then echo "{\"pass\": false, \"reasoning\": \"MOCK code: $f does nothing\"}"; exit 0; fi
done
for t in $(printf '%s\n' "$input" | grep -o '<test path="[^"]*"' | sed 's/.*path="//; s/"$//'); do
  if ! grep -q 'if ' "$root/$t"; then echo "{\"pass\": false, \"reasoning\": \"MOCK tests: $t asserts nothing\"}"; exit 0; fi
done
echo '{"pass": true, "reasoning": ""}'
