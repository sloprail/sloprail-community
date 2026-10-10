---
concern: the size of Go files
sloprails: [gate/file-size, file-guard/file-size]
limits:
  go: 150         # non-test Go
  go_test: 400    # *_test.go
ceilings: {}
---

# Go files stay small

## Concern

The size of every Go file in the repository.

## Decision

- A non-test Go file has at most `limits.go` lines. A test file has at most
  `limits.go_test` lines.
- New code is split by responsibility into files within the limit.
- A test that would outgrow its limit by listing variations moves them into a case file
  (`testdata/<name>.jsonl`, `adr/file-placement`) and loops over it. A case file has no limit.
