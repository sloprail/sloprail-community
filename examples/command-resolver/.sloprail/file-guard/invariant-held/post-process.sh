#!/usr/bin/env bash
# post_process: turns the judge's answer (response.schema.json) into the check's verdict.
#
#   stdin            the answer: {pass, reasoning, invariants: {"<domain>/<id>": {code, tests}}}
#   SR_JUDGE_INPUT   what the prompt was rendered with: the invariants prepare.sh listed
#
# 1. The table must hold exactly the invariants the judge was given (prepare.sh's list, read
#    back from SR_JUDGE_INPUT, not worked out again). One missing or one unknown: exit 65, and
#    the judge is asked again with the sentence written to stderr.
# 2. The verdict is the table's: pass when every cell is "pass". The judge's own `pass` is not
#    trusted when it contradicts its table; it is kept in the metadata as `judge_pass`.
# 3. On a fail the reasoning shown to the agent names the failing invariants and halves, then
#    gives the judge's own reasoning.
# 4. metadata: {bucket, invariants: [{invariant, code, tests, code_at, tests_at}], unjudged,
#    judge_pass}. code_at and tests_at are [{path, line}] of every `sr:invariant <id>` and
#    `sr:proves <id>` marker in the judged head, found here with git grep, never by the model.
#    unjudged are the bucket's invariants that carry neither marker: the judge was not shown them.
# Any other failure exits 1 with its reason on stderr: the check then refuses without a verdict.
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
  [$in[0].additionalContext.invariants[].id] as $want | ((.invariants // {}) | keys) as $got
  | (($want - $got) | map("no entry for the invariant \(.)"))
    + (($got - $want) | map("\(.) is not an invariant you were given"))
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
  $in[0] as $i | . as $a
  | [$i.additionalContext.invariants[] | .id as $id
     | {invariant: $id, code: $a.invariants[$id].code, tests: $a.invariants[$id].tests,
        code_at: at($code; $id), tests_at: at($tests; $id)}] as $rows
  | [$rows[] | select(.code == "fail" or .tests == "fail")
     | "\(.invariant) (\([(select(.code == "fail") | "code"), (select(.tests == "fail") | "tests")] | join(", ")))"] as $failing
  | {pass: ($failing | length == 0),
     reasoning: (if ($failing | length) == 0 then ($a.reasoning // "")
                 else "Failing: \($failing | join("; ")).\n\n\($a.reasoning // "")" end),
     metadata: {bucket: ($i.subject.id // null), invariants: $rows,
                unjudged: ($i.additionalContext.unmarked // []), judge_pass: $a.pass}}' <<<"$answer" ||
  fail "the verdict could not be worked out from the judge's answer"
