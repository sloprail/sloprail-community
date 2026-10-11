#!/usr/bin/env bash
# Mock judge for spec-quality. Keeps its prompt (PROMPT_LOG), then decides like the real one on
# one point of the document-invariant skill: an invariant whose predicate reaches an open-ended
# space ("valid shell syntax", "any valid") is not concrete. It refuses only when the skill's
# rule on concreteness is in its prompt, so a skill that no longer reaches the judge fails the
# case instead of passing it.
# stdin is the rendered prompt, then the check's payload as one JSON line (a mock's extra; a
# model gets the prompt alone). Only the prompt is kept and read.
input="$(grep -v '^{"event":' )"
printf '%s\n' "$input" >> "$PROMPT_LOG"
if ! printf '%s\n' "$input" | grep -q '^### An invariant is concrete'; then
  echo '{"pass": true, "reasoning": "MOCK: no rule on concreteness in the prompt"}'; exit 0
fi
bad="$(printf '%s\n' "$input" | awk '/^## The files to judge/{on=1} /^## Entities they cite/{on=0} on && /^<file path="/{p=$0} on && p && /valid shell syntax|any valid/{print p}' | sed 's/.*path="//; s/".*//' | sort -u | tr '\n' ' ')"
if [ -n "$bad" ]; then
  echo "{\"pass\": false, \"reasoning\": \"MOCK not concrete: $bad\"}"; exit 0
fi
echo '{"pass": true, "reasoning": ""}'
