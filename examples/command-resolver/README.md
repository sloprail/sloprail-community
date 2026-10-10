# command-resolver

A template for growing a whole tool under sloprail: a bash command resolver,
specified as invariants, built once with these rules and once without.

- `template/`: what every run starts from. `CLAUDE.md`, `spec/` (13 entities, 125 invariants), `config/builtin.yaml` and `adr/` (the four decisions `CLAUDE.md` links: markers, modules, file size, file placement).
- `.sloprail/`: the rules that check those decisions. Only the `sloprail` variant gets them.
- `prepare.sh`: turns the project into one variant. `sloprail` leaves it as copied; `bare` removes `.sloprail/` and the line of each ADR that names its rules. Nothing else differs.
- `eval/build/`: the one fixture. `prompt.md` is the whole instruction: build it, ask nothing, the invariants are the only source of truth, stop when all hold.

## The rules

| Rule | What it holds | Judge calls | From |
|---|---|---|---|
| `gate/givens-frozen`, `file-guard/givens-frozen` | nothing under `spec/`, `config/`, `adr/`, `.sloprail/`, nor `CLAUDE.md`, is added, changed or removed | 0 | written here |
| `file-guard/structure.yaml` | where files may be written (`adr/file-placement`) | 0 | written here |
| `file-guard/invariant-covered` | every invariant has marked code and a marked test | 0 | sloprail, changed to check every invariant instead of the touched ones |
| `file-guard/invariant-held` | the marked code upholds its invariant and the marked tests prove it | 1 per bucket of 10 invariants touched, 13 at most | sloprail's `invariant-upheld` and `invariant-rigor`, merged |
| `gate/file-size`, `file-guard/file-size` | Go files at most 150 lines, tests 400 (`adr/file-size`) | 0 | harness-mocks |
| `file-guard/module-coverage` | every Go file under `internal/` is in exactly one module | 0 | harness-mocks |
| `file-guard/module-boundaries` | a module is imported only through its `api` | 0 | harness-mocks |
| `file-guard/module-distinct` | no two modules share a concern | as in harness-mocks | harness-mocks |
| `file-guard/module-leaks` | a module's logic stays in its home | as in harness-mocks | harness-mocks |

`invariant-held` hands its judge paths, not text: per invariant, its spec file
and the files carrying `sr:invariant` / `sr:proves` for it. The judge reads them.
Its rubric is the two original rubrics, kept word for word, as two questions.

The module and file-size rules read `adr/*/ADR.md` and need `yq`; the fixture
runs `freshMachine`, so the plugin's `install.sh` installs it.

## Status

Draft. The invariants await sign-off. No rule here has been run against a real
agent. `eval/build` needs an sr-eval that knows `--variant`
(sloprail/sloprail, branch `feat/sr-eval-variants`):

```
sr-eval run --fixture examples/command-resolver/eval/build --variant sloprail --model <m>
sr-eval run --fixture examples/command-resolver/eval/build --variant bare     --model <m>
```
