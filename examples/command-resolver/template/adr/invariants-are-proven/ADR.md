---
concern: how the code is tied to the specification
sloprails: [file-guard/invariant-covered, file-guard/invariant-held, gate/givens-frozen, file-guard/givens-frozen]
---

# Every invariant is marked in the code that upholds it and in a test that proves it

## Concern

How a reader gets from an invariant in `spec/` to the code that keeps it true and
the test that shows it, and back.

## Decision

An invariant's id is `<domain>/<id>`: its domain folder and its file name.
`spec/words/invariants/quotes-are-removed.yaml` is `words/quotes-are-removed`.

- The specification is fixed. No file under `spec/` is added, changed or removed. The same goes for `config/`, `adr/` and `CLAUDE.md`.
- The code that makes an invariant true carries, on its own line directly above
  it, the comment `// sr:invariant words/quotes-are-removed`. The marker sits on the function or block that does the work, not on a file
  header or a dispatcher that only calls it. Code that upholds several
  invariants carries one marker line for each.
- A test that proves an invariant carries, on its own line directly above the
  test function, the comment `// sr:proves words/quotes-are-removed`.

- `sr:invariant` appears only in non-test files, `sr:proves` only in `_test.go` files.
- Every invariant has at least one of each. A marker names an invariant that exists.
- The marked code does what the predicate says under its exact wording, not a
  looser or stricter reading.
- The tests of an invariant, together, prove it: each drives the tool through
  its real interface (a line in, a `Resolution` out) and would fail if the tool
  broke the predicate; between them they exercise every condition the predicate
  names, its edges and what must not happen. A test that only checks "no
  error", or a helper, proves nothing.
