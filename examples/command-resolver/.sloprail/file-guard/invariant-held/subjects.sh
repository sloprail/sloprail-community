#!/usr/bin/env bash
# subjects: one per invariant the change touches, id `<domain>/<id>`, in the batch of its bucket
# (buckets.sh): the invariants of one bucket are judged by one call, each given its own verdict.
# An invariant is touched when its spec file changed, a changed file carries (before or after)
# sr:invariant or sr:proves naming it, or a case file its marked tests name changed.
#   files        the changed files that touch the invariant
#   fingerprint  everything the judge reads for it: its spec file, every file carrying one of
#                its markers, changed or not, and the case files its marked tests name
#   batch        its bucket
# A case file (testdata/<name>.jsonl) is an invariant's when it sits in the testdata/ folder
# beside one of its marked tests and that test names `<name>.jsonl` literally: its cases are the
# test's inputs. A change to one invariant leaves every other invariant's verdict as it was.
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
slim_payload
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/subjects.sh"
. "${SR_GUARDRAIL_DIR:-.}/buckets.sh"
load_buckets
code="$(markers_json invariant)"; tests="$(markers_json proves)"
# the case files at the head, and the changed ones (a deleted case file is still a change to
# the tests that name it)
head_cases="$(git -C "$SR_TREE" ls-files -- '*testdata/*.jsonl')" ||
  refuse_error "the case files could not be listed, so an invariant cannot be keyed by them"
cases="$(printf '%s\n%s\n' "$head_cases" "$(changed_paths)" |
  jq -Rnc '[inputs | select(test("(^|/)testdata/[a-z0-9_]+[.]jsonl$"))] | unique')"
# which marked test names which case file: one git grep of every marked test for every case
# file's name, as [{t: test, n: name}]
named='[]'
mapfile -t tpaths < <(jq -r '[.[].p] | unique | .[]' <<<"$tests")
pats=(); while IFS= read -r n; do [ -n "$n" ] && pats+=(-e "$n"); done < <(jq -r 'map(sub("^.*/"; "")) | unique | .[]' <<<"$cases")
if [ "${#tpaths[@]}" -gt 0 ] && [ "${#pats[@]}" -gt 0 ]; then
  out="$(git -C "$SR_TREE" grep -I -o -F "${pats[@]}" -- "${tpaths[@]}" 2>&1)"; rc=$?
  [ "$rc" -le 1 ] || refuse_error "the marked tests could not be searched for the case files they name: $out"
  named="$(printf '%s\n' "$out" | jq -Rnc '[inputs | select(length > 0) | capture("^(?<t>.*):(?<n>[^:]*)$")] | unique')"
fi
arr="$(printf '%s' "$payload" | jq -c --argjson b "$BUCKETS" --argjson code "$code" --argjson tests "$tests" \
    --argjson cases "$cases" --argjson named "$named" '
  def dir: if test("/") then sub("/[^/]*$"; "") else "" end;
  [.changeset.files[] | {path, ids: [((.newMarkers // []) + (.oldMarkers // []))[]
     | select(.kind == "invariant" or .kind == "proves") | .fqn]}] as $cf
  | [$b[] | .id as $id | .path as $spec
     | ([$tests[] | select(.q == $id) | .p] | unique) as $tp
     | ([$cases[] | . as $c | select(any($tp[]; . as $t
          | ($c | dir | dir) == ($t | dir)
            and ($named | index([{t: $t, n: ($c | sub("^.*/"; ""))}]) != null)))]) as $ic
     | {id, batch: .bucket,
        files: [$cf[] | select(.path == $spec or (.path as $p | $ic | index($p)) != null
                  or (.ids | index($id)) != null) | .path],
        deps: ([$spec] + $ic + [($code + $tests)[] | select(.q == $id) | .p] | unique)}
     | select(.files | length > 0)]')" ||
  refuse_error "the invariants the change touches could not be worked out"
# sub_finish keeps only {id, files, fingerprint}: put each subject's batch back on it
out="$(sub_finish unclaimed "$arr")" || exit $?
jq -c --argjson a "$arr" '($a | map({(.id): .batch}) | add // {}) as $bt
  | map(if $bt[.id] then . + {batch: $bt[.id]} else . end)' <<<"$out"
