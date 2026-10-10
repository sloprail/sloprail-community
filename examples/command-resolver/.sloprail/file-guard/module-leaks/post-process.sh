#!/usr/bin/env bash
# post_process: turns the judge's answer (response.schema.json) into the check's verdict.
#
#   stdin            the answer: {pass, reasoning, candidates: [{path, line, verdict}]}
#   SR_JUDGE_INPUT   what the prompt was rendered with: the module and the candidates
#                    find-leaks.sh left for the judge (the lines of its matches file)
#
# 1. The answer must classify exactly the candidates the judge was given, by path and line. One
#    missing, one that was not given, or one called both a leak and a use: exit 65, and the
#    judge is asked again with the sentence written to stderr.
# 2. The verdict is the list's: pass when no candidate is a leak. The judge's own `pass` is not
#    trusted when it contradicts its list; it is kept in the metadata as `judge_pass`.
# 3. On a fail the reasoning shown to the agent names each leak's path and line, then gives the
#    judge's own reasoning.
# 4. metadata: {module, candidates: [{path, line, verdict}], leaks, uses, judge_pass}. Metadata
#    is bounded (64 KiB) and a module's candidates are not, so past MAX_METADATA bytes the list
#    keeps the leaks only, then nothing, and says so with `truncated: true`; `leaks` and `uses`
#    always count them all.
# Any other failure exits 1 with its reason on stderr: the check then refuses without a verdict.
set -uo pipefail
MAX_METADATA=60000
answer="$(cat)"
fail() { echo "$1" >&2; exit 1; }
[ -n "${SR_JUDGE_INPUT:-}" ] && [ -f "$SR_JUDGE_INPUT" ] || fail "SR_JUDGE_INPUT names no file, so the candidates the judge was given are unknown"
# The rule is split by module (subjects.sh), so a call holds one module: a list that names no
# module cannot be told apart between two.
n="$(jq '.additionalContext.modules | length' "$SR_JUDGE_INPUT")" || fail "the judge's input could not be read"
[ "$n" -eq 1 ] || fail "the judge was given $n modules in one call; this check judges one module per call"

problems="$(jq -r --slurpfile in "$SR_JUDGE_INPUT" '
  def key: "\(.path):\(.line)";
  [$in[0].additionalContext.modules[0].candidates[] | key] as $want
  | ((.candidates // []) | group_by(key)) as $g | [$g[] | .[0] | key] as $got
  | (($want - $got) | map("no verdict for the match \(.)"))
    + (($got - $want) | map("\(.) is not a match you were given"))
    + [$g[] | select(([.[].verdict] | unique | length) > 1) | "\(.[0] | key) is called both a leak and a use"]
  | join("; ")' <<<"$answer")" || fail "the judge's answer could not be compared with the candidates it was given"
if [ -n "$problems" ]; then
  echo "$problems. Give one entry in \`candidates\` for each line of the matches file, with its path and line as given there, and for nothing else." >&2
  exit 65
fi

result() {   # result KEEP — the check's result, its metadata listing: all | leaks | none
  jq -c --slurpfile in "$SR_JUDGE_INPUT" --arg keep "$1" '
    def key: "\(.path):\(.line)";
    $in[0].additionalContext.modules[0] as $m | . as $a
    | (reduce $a.candidates[] as $c ({}; .[$c | key] = $c.verdict)) as $v
    | [$m.candidates | unique_by(key)[] | {path, line, verdict: $v[key]}] as $rows
    | [$rows[] | select(.verdict == "leak")] as $leaks
    | {pass: ($leaks | length == 0),
       reasoning: (if ($leaks | length) == 0 then ($a.reasoning // "")
                   else "Leaks of \($m.module): \($leaks | map(key) | join("; ")).\n\n\($a.reasoning // "")" end),
       metadata: ({module: $m.module,
                   candidates: (if $keep == "all" then $rows elif $keep == "leaks" then $leaks else [] end),
                   leaks: ($leaks | length), uses: (($rows | length) - ($leaks | length)), judge_pass: $a.pass}
                  + (if $keep == "all" then {} else {truncated: true} end))}' <<<"$answer"
}
for keep in all leaks none; do
  out="$(result "$keep")" || fail "the verdict could not be worked out from the judge's answer"
  size="$(jq -c '.metadata' <<<"$out" | wc -c)" || fail "the metadata could not be measured"
  if [ "$size" -le "$MAX_METADATA" ] || [ "$keep" = none ]; then printf '%s\n' "$out"; exit 0; fi
done
