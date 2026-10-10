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
| `README.md`, `CLAUDE.md`, `.gitignore`, `go.mod`, `go.sum` | the repository itself |

- Go file and directory names are lowercase letters, digits and `_`.
- A test sits beside the code it tests, as `<file>_test.go`.
- Nothing else is added: no `pkg/`, `scripts/`, `docs/`, `testdata/` or files at the root.
