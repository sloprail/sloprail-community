# How to answer

Your last message is the whole review: nothing else you write is read.

1. Its first line is `REVIEW: clean` when you found no failure at all, and `REVIEW: findings`
   otherwise.
2. Then the verdicts, in the order of the sections above and in the form each section asks
   for: `pass` or `fail` for every invariant, every module and every rule you were asked to
   cover, each with the reasoning its section requires. A verdict without that reasoning is
   not a pass.
3. Then `Findings:`, one numbered entry for every failure: the invariant, module or rule it
   is about, the file and line, the exact clause or rule it breaks, and what to do about it.
   With no failure, write `Findings: none`.

A failure is a finding, not advice: do not soften one, and do not add remarks that are not
failures of something these instructions ask you to check.
