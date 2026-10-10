#!/usr/bin/env bash
# prepare: the invariants of the bucket this check's subject names (subjects.sh), as
# additionalContext.invariants. Each carries its id, the path of its spec file, the paths of
# the files marked sr:invariant <id> (code) and of the files marked sr:proves <id> (tests).
# Paths only: the judge reads the files. An invariant with neither marker yet is left out:
# there is nothing to judge, and its absence is invariant-covered's finding.
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
. "${SR_GUARDRAIL_DIR:-.}/buckets.sh"

[ "$(cs '.event.kind // ""')" = "Changeset" ] \
  || refuse "The check payload is not a Changeset, so the invariants could not be listed for the judge."

load_buckets
code="$(markers_json invariant)"; tests="$(markers_json proves)"
want="$(subject_id)"
invariants="$(jq -nc --argjson b "$BUCKETS" --argjson code "$code" --argjson tests "$tests" --arg want "$want" '
  [$b[] | select($want == "" or .bucket == $want) | .id as $id
   | {id, path,
      code: ([$code[] | select(.q == $id) | .p] | unique),
      tests: ([$tests[] | select(.q == $id) | .p] | unique)}
   | select((.code + .tests) | length > 0)]')"
if [ "$(jq 'length' <<<"$invariants")" -eq 0 ]; then echo '{"skip": true}'; exit 0; fi
jq -n -c --argjson i "$invariants" '{additionalContext: {invariants: $i}}'
