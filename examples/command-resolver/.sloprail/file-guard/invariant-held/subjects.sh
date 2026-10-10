#!/usr/bin/env bash
# subjects: one per bucket of invariants (buckets.sh) the change touches: a spec file of the
# bucket changed, or a changed file carries (before or after) sr:invariant or sr:proves naming
# one of its invariants.
#   files        the changed files that touch the bucket
#   fingerprint  everything the judge reads for it: the bucket's spec files and every file
#                marked for one of its invariants, changed or not.
# A change to an invariant of one bucket leaves every other bucket's verdict as it was.
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
slim_payload
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/subjects.sh"
. "${SR_GUARDRAIL_DIR:-.}/buckets.sh"
load_buckets
code="$(markers_json invariant)"; tests="$(markers_json proves)"
arr="$(printf '%s' "$payload" | jq -c --argjson b "$BUCKETS" --argjson code "$code" --argjson tests "$tests" '
  [.changeset.files[] | {path, ids: [((.newMarkers // []) + (.oldMarkers // []))[]
     | select(.kind == "invariant" or .kind == "proves") | .fqn]}] as $cf
  | ($code + $tests) as $m
  | $b | group_by(.bucket) | map(
      (map(.id)) as $ids | (map(.path)) as $paths
      | {id: .[0].bucket,
         files: [$cf[] | select((.path as $p | $paths | index($p)) != null
                   or any(.ids[]; . as $i | ($ids | index($i)) != null)) | .path],
         deps: ($paths + [$m[] | select(.q as $q | ($ids | index($q)) != null) | .p] | unique)})
  | map(select(.files | length > 0))')"
sub_finish unclaimed "$arr"
