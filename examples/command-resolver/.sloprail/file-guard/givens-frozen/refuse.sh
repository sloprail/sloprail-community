#!/usr/bin/env bash
# Any selected file is a change to a given file: refuse, naming them.
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
changed="$(cs '.changeset.files[] | "- \(.path) (\(.status))"')"
[ -n "$changed" ] || exit 0
refuse "These files are given and fixed, and this change touches them:
${changed}
Restore them to what they were in the first commit and change the code or its tests so they meet the invariants and the ADRs as written. If an invariant looks wrong or two contradict each other, leave them as they are and say so in your final message."
