# command-resolver

A template for growing a whole tool under sloprail: a bash command resolver,
specified as invariants, built once with these rules, once without, and three
times without them but with the builder's own reviewers.

- `template/`: what every run starts from. `CLAUDE.md`, `spec/` (13 entities, 125 invariants), `config/builtin.yaml` and `adr/` (the four decisions `CLAUDE.md` links: markers, modules, file size, file placement).
- `.sloprail/`: the rules that check those decisions. Only the `sloprail` variant gets them.
- `prepare.sh`: turns the project into one variant (below).
- `review-src/`: what the review variants are made of, beside the judges' own templates.
- `eval/build/`: the one fixture. `prompt.md` is the whole instruction, the same for every variant: build it, ask nothing, the invariants are the only source of truth, stop when all hold.

## The variants

| Variant | The project | Who checks the work |
|---|---|---|
| `sloprail` | `template/` and `.sloprail/` | the rules below, at every write and every stop |
| `bare` | `template/` alone: no `.sloprail/`, and no line of an ADR naming its rules | nobody |
| `review-whole` | `bare`, `review/review.md` and a last section of `CLAUDE.md` | one reviewer reads everything; the builder fixes and has everything read again, until a review finds nothing |
| `review-batched` | `bare`, `review/invariants.md`, `review/modules.md`, `review/rules.md` and a last section of `CLAUDE.md` | one reviewer per batch of ten invariants (the buckets of `invariant-held/buckets.sh`), one for the modules, one for the mechanical rules; after a fix only those whose material changed are launched again, until all are clean |
| `review-once` | as `review-whole` | one reviewer reads everything once; its findings are fixed and nothing is read again |

The three review variants ask whether a reviewer alone is enough. They run without
sloprail (`noSloprail`, like `bare`): a reviewer is a sub-agent the builder launches itself,
with its own model and reasoning effort, read-only, because the last section of `CLAUDE.md`
tells it to. Nothing outside the session holds it to that. Nothing else differs from `bare`.

`review/` is written by `prepare.sh` from the rules, so a reviewer is asked what a judge is:

- The three judged rules (`invariant-held`, `module-distinct`, `module-leaks`) go in word for
  word. Only a template's block of plumbing, the lines that inject a bucket's invariants or
  the list of modules, is replaced: by `review-src/*.find.md`, which tells the reviewer how to
  find the same material itself. Every other line is the judge's.
- The scripted rules (`givens-frozen`, `structure`, `file-size`, `invariant-covered`,
  `module-coverage`, `module-boundaries`) have no script in such a project. `review-src/rules.md`
  states what each script enforces, and `prepare.sh` fills in the numbers and patterns from
  where the scripts read them: the limits and the module space from the ADRs, the allowed
  paths from `file-guard/structure.yaml`, the batch size from `invariant-held/buckets.sh`.
- `review-src/head.md` and `answer.md` open and close every reviewer's file: it changes
  nothing, and it answers with a verdict per invariant, module and rule and a finding per failure.
- `review-src/claude-<variant>.md` is the section added to `CLAUDE.md`.

`review-src/check.sh` prepares the three variants in a scratch directory and fails when one is
not `bare` plus those two things, when a rubric in `review/` is not the judge's template line
for line, or when the builder's or a reviewer's text names the rules, a judge or a run. Run it
after changing a judge template, `review-src/` or `prepare.sh`. It runs no agent.

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

The four rules written or changed here each have an `sr-test` case beside them
(`sr-test run examples/command-resolver`); the rules copied from harness-mocks
came without cases. `prepare.sh` removes the cases from the project a run starts from.

`invariant-held` hands its judge paths, not text: per invariant, its spec file
and the files carrying `sr:invariant` / `sr:proves` for it. The judge reads them.
Its rubric is the two original rubrics, kept word for word, as two questions.

The module and file-size rules read `adr/*/ADR.md` and need `yq`; the fixture
runs `freshMachine`, so the plugin's `install.sh` installs it.

## Status

Draft. The invariants await sign-off. No rule here has been run against a real
agent, and no review variant either. `eval/build` needs an sr-eval that knows `--variant`
(sloprail/sloprail, branch `feat/sr-eval-variants`):

```
sr-eval run --fixture examples/command-resolver/eval/build --variant sloprail       --model <m>
sr-eval run --fixture examples/command-resolver/eval/build --variant bare           --model <m>
sr-eval run --fixture examples/command-resolver/eval/build --variant review-whole   --model <m>
sr-eval run --fixture examples/command-resolver/eval/build --variant review-batched --model <m>
sr-eval run --fixture examples/command-resolver/eval/build --variant review-once    --model <m>
```
