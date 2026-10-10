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
| `gate/checks-judged` | a turn of the main session does not end while committed work since the rules has no verdict or a failing one; the refusal names the `sr-checks run` command (the engine's own Stop reports stored failures only, and there is no push or pull request here to ask for the rest) | 0 | written here |
| `file-guard/structure.yaml` | where files may be written (`adr/file-placement`) | 0 | written here |
| `file-guard/invariant-covered` | every invariant has marked code and a marked test | 0 | sloprail, changed to check every invariant instead of the touched ones |
| `file-guard/invariant-held` | the marked code upholds its invariant and the marked tests prove it | 1 per bucket of 10 invariants touched, 13 at most | sloprail's `invariant-upheld` and `invariant-rigor`, merged |
| `gate/file-size`, `file-guard/file-size` | Go files at most 150 lines, tests 400 (`adr/file-size`) | 0 | harness-mocks |
| `file-guard/module-coverage` | every Go file under `internal/` is in exactly one module | 0 | harness-mocks |
| `file-guard/module-boundaries` | a module is imported only through its `api` | 0 | harness-mocks |
| `file-guard/module-distinct` | no two modules share a concern | as in harness-mocks | harness-mocks |
| `file-guard/module-leaks` | a module's logic stays in its home | as in harness-mocks | harness-mocks |

The rules written or changed here each have an `sr-test` case beside them
(`sr-test run examples/command-resolver`); so do the three judges' answers (below).
The script-only rules copied from harness-mocks came without cases. `prepare.sh`
removes the cases from the project a run starts from.

`invariant-held` hands its judge paths, not text: per invariant, its spec file
and the files carrying `sr:invariant` / `sr:proves` for it. The judge reads them.
Its rubric is the two original rubrics, kept word for word, as two questions.

## What a judge answers

The three judges answer in a shape of their own (`response.schema.json` beside each
rule), and the rule's `post-process.sh` turns that answer into the verdict. The
prompt's rubric says what to judge; the schema says how to return it.

| Rule | The answer carries | Metadata stored with the verdict |
|---|---|---|
| `invariant-held` | `invariants`: per invariant of the bucket, `code` and `tests`, each `pass` or `fail` | `bucket`; `invariants`: `[{invariant, code, tests, code_at, tests_at}]`; `unjudged`: the bucket's invariants with no marker yet |
| `module-distinct` | `modules`: per changed module, `concern` and `home`, each `pass` or `fail` | `modules`: `[{module, concern, home}]`; `unjudged`: the modules the range did not change |
| `module-leaks` | `candidates`: per match, `path`, `line` and `verdict` (`leak` or `use`) | `module`; `candidates`: `[{path, line, verdict}]`; `leaks`, `uses` |

- The table decides. A check passes when every cell passes (no candidate is a leak).
  The judge's own `pass` is not trusted when it contradicts its table: it is kept in
  the metadata as `judge_pass`, and the verdict is the table's.
- The table is complete or it is not an answer. An entry missing for something the
  judge was given, or an entry for something it was not, sends the answer back to
  the judge (`post-process.sh` exits 65) with the sentence naming it.
- `code_at` and `tests_at` are `[{path, line}]`: every `sr:invariant <id>` and
  `sr:proves <id>` marker in the judged commit, found by the script with `git grep`,
  never by the model.
- On a failure the agent is shown the failing entries by name, then the judge's
  reasoning. The metadata is never shown to the agent; read it with
  `sr-checks show --json --base <rev> --head <rev>` (the judge's row) or
  `sr-checks log --json` (under the step, `check[0]:judge:./<template>`).
- `module-leaks` bounds its metadata: past 60000 bytes the list keeps the leaks
  only, with `truncated: true`; `leaks` and `uses` always count every candidate.

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
