Build the tool this repository specifies.

`CLAUDE.md` says what it is and how the repository is built. `spec/` is the
only source of truth for what the tool does: every invariant under
`spec/*/invariants/` must hold, be marked in the code that upholds it and be
proven by a test.

Work fully autonomously. Nobody is available to answer questions, so do not
ask any and do not stop to check in: where something is unclear, decide from
the invariants and carry on. Do not change anything under `spec/`. If two
invariants seem to contradict each other, keep both files as they are, pick
the reading that breaks the fewest invariants, and say so at the end.

Keep going until every invariant is implemented and proven, `go build ./cmd/resolve`
and `go test ./...` pass, and everything is committed. Only then stop, with a
short account of what you built and anything in the spec you could not satisfy.
