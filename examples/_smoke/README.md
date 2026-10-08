# Smoke evals

A tiny real-agent check that sloprail's business-critical hook paths work on each harness
(claude, codex, cursor). Each case is a one-or-two-file seed, a one-line prompt and a
`size-sm` model, about a minute. They are not examples of a guardrail; for those see the
other `examples/` folders.

| Case | Proves |
|---|---|
| `session-context` | SessionStart context reaches the agent: it acts on an instruction only the hook gives |
| `prewrite-gate` | a PreFileWrite gate refuses a write and the agent recovers |
| `command-gate` | a pre-Bash gate refuses a command |
| `stop-gate` | a Stop gate blocks the end of the turn once and the agent does the owed work |
| `file-guard-stop` | a file-guard refuses a committed bad file at Stop (the `sr-checks verify` path) |
| `citation` | a change that needs `Sloprail-Cites-User` gets one that resolves |
| `skill-required` | a skill-required gate passes once the skill has been read |

Every case is scored on facts of the record (the refusal appeared, the follow-up happened,
the files ended right), read through `sr-session trajectory normalize`, so one scorer serves
all harnesses (`examples/_shared/eval/smoke.sh`).

## Run

```sh
scripts/run-smoke-evals.sh --sloprail ../sloprail      # all cases x claude, codex, cursor
scripts/run-smoke-evals.sh --harness claude --case stop-gate
```

The runner prints a harness x case table. A cell expected to fail is marked in the runner's
`EXPECT_FAIL` list and shows as `XFAIL` (and `XPASS`, a failure, once it starts passing):
Cursor's stop hook does not fire under `-p`, so `stop-gate` and `file-guard-stop` are
expected to fail there until sr-eval runs Cursor in its TUI.

`tests/e2e/harness/examples/053_smoke_evals` proves the fixtures without a real agent: the
mock plays the expected path, and a path that skips the point of the case, and each
`score.sh` must pass the first and fail the second.
