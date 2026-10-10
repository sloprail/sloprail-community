#!/usr/bin/env bash
# Mock judge for module-distinct. Keeps its prompt (appended to PROMPT_LOG) and logs, one line per
# judge call, every module it was shown with whether it is marked changed. Then decides on one
# point of the real rubric: a module whose concern says DUPLICATE repeats another's.
# stdin is the rendered prompt, then the check's payload as one JSON line; only the prompt is read.
input="$(grep -v '^{"event":')"
printf '%s\n' "$input" >> "$PROMPT_LOG"
printf '%s\n' "$(printf '%s\n' "$input" | grep -o '<module dir="[^"]*" changed="[^"]*"' | sed 's/<module dir="//; s/" changed="/=/; s/"$//' | tr '\n' ' ')" >> "$JUDGE_LOG"
dup="$(printf '%s\n' "$input" | grep -B1 '<concern>DUPLICATE' | grep -o '<module dir="[^"]*"' | sed 's/.*dir="//; s/"$//' | head -1)"
if [ -n "$dup" ]; then echo "{\"pass\": false, \"reasoning\": \"MOCK: $dup repeats another concern\"}"; exit 0; fi
echo '{"pass": true, "reasoning": ""}'
