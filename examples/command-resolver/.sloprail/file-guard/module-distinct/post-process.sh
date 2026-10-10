#!/usr/bin/env bash
# post_process: turns the judge's answer (response.schema.json) into the check's verdict.
#
#   stdin            the answer: {pass, reasoning, modules: {"<dir>": {concern, home}}}
#   SR_JUDGE_INPUT   what the prompt was rendered with: the modules prepare.sh listed
#
# 1. The table must hold exactly the modules the judge was asked to judge: those prepare.sh
#    marked changed (the rubric judges the changed modules, against all the others). One
#    missing or one other: exit 65, and the judge is asked again with the sentence on stderr.
# 2. The verdict is the table's: pass when every cell is "pass". The judge's own `pass` is not
#    trusted when it contradicts its table; it is kept in the metadata as `judge_pass`.
# 3. On a fail the reasoning shown to the agent names the failing modules and cells, then
#    gives the judge's own reasoning.
# 4. metadata: {modules: [{module, concern, home}], unjudged, judge_pass}. unjudged are the
#    modules the range did not change: shown to the judge to compare with, not judged.
# Any other failure exits 1 with its reason on stderr: the check then refuses without a verdict.
set -uo pipefail
answer="$(cat)"
fail() { echo "$1" >&2; exit 1; }
[ -n "${SR_JUDGE_INPUT:-}" ] && [ -f "$SR_JUDGE_INPUT" ] || fail "SR_JUDGE_INPUT names no file, so the modules the judge was given are unknown"

problems="$(jq -r --slurpfile in "$SR_JUDGE_INPUT" '
  [$in[0].additionalContext.modules[] | select(.changed) | .dir] as $want | ((.modules // {}) | keys) as $got
  | (($want - $got) | map("no entry for the module \(.)"))
    + (($got - $want) | map("\(.) is not a module marked changed=\"true\""))
  | join("; ")' <<<"$answer")" || fail "the judge's answer could not be compared with the modules it was given"
if [ -n "$problems" ]; then
  echo "$problems. Give one entry in \`modules\` for each <module> above marked changed=\"true\", keyed by its dir, and for no other." >&2
  exit 65
fi

jq -c --slurpfile in "$SR_JUDGE_INPUT" '
  $in[0].additionalContext.modules as $m | . as $a
  | [$m[] | select(.changed) | .dir as $d
     | {module: $d, concern: $a.modules[$d].concern, home: $a.modules[$d].home}] as $rows
  | [$rows[] | select(.concern == "fail" or .home == "fail")
     | "\(.module) (\([(select(.concern == "fail") | "concern"), (select(.home == "fail") | "home")] | join(", ")))"] as $failing
  | {pass: ($failing | length == 0),
     reasoning: (if ($failing | length) == 0 then ($a.reasoning // "")
                 else "Failing: \($failing | join("; ")).\n\n\($a.reasoning // "")" end),
     metadata: {modules: $rows, unjudged: [$m[] | select(.changed | not) | .dir], judge_pass: $a.pass}}' <<<"$answer" ||
  fail "the verdict could not be worked out from the judge's answer"
