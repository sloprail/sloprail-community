---
concern: where each kind of file lives
sloprails: [file-guard/structure]
---

# Every file has a declared place

## Concern

Where files are created, so the repository can be read from its layout alone.

## Decision

Only these paths exist:

| Path | What it is |
|---|---|
| `spec/<domain>/entities/<Entity>.yaml`, `spec/<domain>/invariants/<id>.yaml` | the specification (given) |
| `config/builtin.yaml` | the built-in program tables (given) |
| `adr/<name>/ADR.md` | a decision about how this repository is built |
| `cmd/<name>/<file>.go` | a command's entry point: flags, input, output, nothing else |
| `internal/<module>/…/<file>.go` | the code, in modules (`adr/modules-cover-code`) |
| `internal/<module>/…/module.yaml` | a module's boundary |
| `internal/<module>/…/testdata/<name>.jsonl` | the cases a test beside it loops over, one case per line |
| `tests/<feature>/<file>_test.go` | end-to-end tests of the built tool, grouped by feature (a spec domain: `tests/words/`, `tests/wrappers/`) |
| `tests/<feature>/testdata/<name>.jsonl` | the cases an end-to-end test loops over |
| `README.md`, `CLAUDE.md`, `.gitignore`, `go.mod`, `go.sum` | the repository itself |

- Go file and directory names are lowercase letters, digits and `_`.
- A test of one module's own behaviour sits beside the code it tests, as `<file>_test.go`.
- A test that runs the tool as a whole (a line in, a resolution out) belongs to no single
  module: it goes under `tests/<feature>/`, with the feature it proves as its folder.
- A test that checks many variations of one behaviour keeps the variations as data: one JSON
  object per line in `testdata/<name>.jsonl` beside it (the input, what is expected, and a
  name for the case), and one test that loops over them. Case files have no line limit
  (`adr/file-size`); the test that reads them stays short.
- Nothing else is added: no `pkg/`, `scripts/`, `docs/` or files at the root, and no data
  file other than a test's cases.
