#!/usr/bin/env bash
# prepare: once per batch (subjects.sh), the batch's invariants as additionalContext.invariants.
# Each carries its id, the path of its spec file, the paths of the files marked
# sr:invariant <id> (code) and of the files marked sr:proves <id> (tests). Paths only: the
# judge reads the files. An invariant with neither marker yet is left out: there is nothing to
# judge, and its absence is invariant-covered's finding. Their ids go in
# additionalContext.unmarked, which the prompt does not use: post-process.sh passes them.
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
. "${SR_GUARDRAIL_DIR:-.}/buckets.sh"

[ "$(cs '.event.kind // ""')" = "Changeset" ] \
  || refuse "The check payload is not a Changeset, so the invariants could not be listed for the judge."

load_buckets
code="$(markers_json invariant)"; tests="$(markers_json proves)"
# the batch's invariants; a subject outside any batch (subjects.sh's `unclaimed`) is none. An
# invariant handed alone as `subject` means a sloprail that does not batch: it would be judged
# with no way to answer for it, so the check fails closed rather than pass it unjudged.
case "$(subject_id)" in
  "" | unclaimed) ;;
  *) refuse_error "invariant-held puts its subjects in batches, and this sloprail handed one alone; it needs a sloprail with batched file-guards" ;;
esac
want="$(cs_json '[(.batch.subjects // [])[].id]')"
listed="$(jq -nc --argjson b "$BUCKETS" --argjson code "$code" --argjson tests "$tests" --argjson want "$want" '
  [$b[] | select(.id as $id | $want | index($id)) | .id as $id
   | {id, path,
      code: ([$code[] | select(.q == $id) | .p] | unique),
      tests: ([$tests[] | select(.q == $id) | .p] | unique)}]
  | {invariants: map(select((.code + .tests) | length > 0)),
     unmarked: map(select((.code + .tests) | length == 0) | .id)}')"
if [ "$(jq '.invariants | length' <<<"$listed")" -eq 0 ]; then echo '{"skip": true}'; exit 0; fi
jq -n -c --argjson l "$listed" '{additionalContext: $l}'
