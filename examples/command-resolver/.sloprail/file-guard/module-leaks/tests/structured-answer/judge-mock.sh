#!/usr/bin/env bash
# Mock judge for module-leaks: keeps its prompt (appended to PROMPT_LOG), then answers with the
# file $ANSWER names, whatever it is asked.
# stdin is the rendered prompt, then the check's payload as one JSON line; only the prompt is kept.
grep -v '^{"event":' >> "$PROMPT_LOG"
cat "$ANSWER"
