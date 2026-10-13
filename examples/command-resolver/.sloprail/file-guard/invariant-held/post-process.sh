#!/usr/bin/env bash
# post_process: turns the judge's answer (response.schema.json) into one verdict per invariant
# of the batch.
#
#   stdin            the answer: {invariants: {"<domain>/<id>": {code, tests, reasoning}}}
#   SR_JUDGE_INPUT   what the prompt was rendered with: the batch, and the invariants
#                    prepare.sh listed (additionalContext.invariants) or left out (.unmarked)
#
# 1. The table must hold every invariant the judge was given (prepare.sh's list, read back from
#    SR_JUDGE_INPUT, not worked out again) and nothing outside the batch. One missing or one
#    unknown: exit 65, and the judge is asked again with the sentence written to stderr. An
#    entry for an unmarked invariant of the batch is ignored.
# 2. Prints {"verdicts": {"<id>": {pass, reasoning, metadata}}} with exactly the batch's ids:
#    - a listed invariant passes when its `code` and `tests` both pass; its reasoning is its own
#      block, after the failing halves on a fail; its metadata is its row:
#      {bucket, invariant, code, tests, code_at, tests_at}. code_at and tests_at are
#      [{path, line}] of every `sr:invariant <id>` and `sr:proves <id>` marker in the judged
#      head, found here with git grep, never by the model.
#    - an unmarked invariant passes unjudged: there was nothing to judge, and the missing marker
#      is invariant-covered's finding. Its metadata is {bucket, invariant, unjudged: true}.
# Any other failure exits 1 with its reason on stderr: the batch then gets no verdict.
set -uo pipefail
answer="$(cat)"
fail() { echo "$1" >&2; exit 1; }
[ -n "${SR_JUDGE_INPUT:-}" ] && [ -f "$SR_JUDGE_INPUT" ] || fail "SR_JUDGE_INPUT names no file, so the invariants the judge was given are unknown"
[ -n "${SR_TREE:-}" ] && [ -d "$SR_TREE" ] || fail "SR_TREE is not set, so the markers of the judged head cannot be found"
payload='{}'   # changeset.sh reads a check's payload; only its marker search is used here
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
refuse() { fail "$1"; }
refuse_error() { fail "$1"; }

problems="$(jq -r --slurpfile in "$SR_JUDGE_INPUT" '
  [$in[0].additionalContext.invariants[].id] as $want
  | [$in[0].batch.subjects[].id] as $batch | ((.invariants // {}) | keys) as $got
  | (($want - $got) | map("no entry for the invariant \(.)"))
    + (($got - $batch) | map("\(.) is not an invariant you were given"))
  | join("; ")' <<<"$answer")" || fail "the judge's answer could not be compared with the invariants it was given"
if [ -n "$problems" ]; then
  echo "$problems. Give one entry in \`invariants\` for each <invariant> id above, and for no other." >&2
  exit 65
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/sr-post-invariant-held.XXXXXX")" || fail "cannot make a directory for the markers"
trap 'rm -rf "$work"' EXIT
load_marker_lines invariant; printf '%s\n' "$MARKER_LINES" >"$work/code"
load_marker_lines proves; printf '%s\n' "$MARKER_LINES" >"$work/tests"

jq -c --slurpfile in "$SR_JUDGE_INPUT" --rawfile code "$work/code" --rawfile tests "$work/tests" '
  def at($raw; $id): [$raw | split("\n")[] | select(length > 0) | split("\t") | select(.[2] == $id)
                      | {path: .[0], line: (.[1] | tonumber)}];
  $in[0] as $i | . as $a | $i.batch.id as $bucket
  | {verdicts: (
      [($i.additionalContext.invariants[] | .id as $id | $a.invariants[$id] as $e
        | {invariant: $id, code: $e.code, tests: $e.tests, code_at: at($code; $id), tests_at: at($tests; $id)} as $row
        | [(select($e.code == "fail") | "code"), (select($e.tests == "fail") | "tests")] as $failing
        | {($id): {pass: ($failing | length == 0),
                   reasoning: (if ($failing | length) == 0 then $e.reasoning
                               else "Failing: \($failing | join(", ")).\n\n\($e.reasoning)" end),
                   metadata: ({bucket: $bucket} + $row)}}),
       (($i.additionalContext.unmarked // [])[] as $id
        | {($id): {pass: true, reasoning: "Not judged: no file carries a marker for it.",
                   metadata: {bucket: $bucket, invariant: $id, unjudged: true}}})]
      | add)}' <<<"$answer" ||
  fail "the verdicts could not be worked out from the judge's answer"
