# command-resolver

A template for growing a whole tool under sloprail: a bash command resolver,
specified as invariants, built once with these rules and once without.

- `template/`: what every run starts from. `CLAUDE.md`, `spec/` (entities and invariants) and `config/builtin.yaml`. Nothing in it mentions sloprail.
- `.sloprail/` and `sloprail-arm/`: what only the sloprail run gets on top.

## The rules

| Rule | What it holds | Copied from |
|---|---|---|
| `file-guard/structure.yaml` | where files may be written | written for this example |
| `file-guard/invariant-covered` | every invariant touched has marked code and a marked test | sloprail |
| `file-guard/invariant-upheld` | the marked code still upholds its invariant (judge) | sloprail |
| `file-guard/invariant-rigor` | the tests of an invariant prove it (judge) | sloprail |
| `gate/file-size`, `file-guard/file-size` | Go files at most 150 lines, tests 400 (`adr/file-size`) | harness-mocks |
| `file-guard/module-coverage` | every Go file under `internal/` is in exactly one module (`module.yaml`) | harness-mocks |
| `file-guard/module-boundaries` | a module is imported only through its `api` | harness-mocks |
| `file-guard/module-distinct` | no two modules share a concern (judge) | harness-mocks |
| `file-guard/module-leaks` | a module's logic stays in its home (judge) | harness-mocks |

The module and file-size rules read `adr/*/ADR.md` and need `yq` on PATH.

## Status

Draft. The invariants await sign-off, the eval fixtures are not written yet, and
no rule here has been run against a real agent.
