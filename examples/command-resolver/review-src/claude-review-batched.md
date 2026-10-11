## Review before you finish

`review/` is given and fixed, like `spec/`: never add, change or remove a file under it.

The work is not finished until every part of it has been reviewed and found clean. Reviews run
in rounds. Start the first round once everything is implemented, `go build ./cmd/resolve` and
`go test ./...` pass and everything is committed.

**The reviewers.** Each is a sub-agent you launch, running the same model as yours at the same
reasoning effort as yours. Its instructions are the full text of one file under `review/`,
word for word, with nothing added, removed or summarised, followed only by what the list
below names.

- **One per batch of invariants**: `review/invariants.md`, followed by the batch's name and the
  paths of its spec files. The batches are fixed: list the invariant files with
  `ls spec/*/invariants/*.yaml | LC_ALL=C sort`; the first @BATCH_SIZE@ are batch `b01`, the next @BATCH_SIZE@ `b02`,
  and so on, the last batch holding what is left.
- **One for the modules**: `review/modules.md`.
- **One for the repository's rules**: `review/rules.md`.

**Which to launch in a round.** In the first round, all of them. After that, each reviewer
whose material changed since the commit it last reviewed with no findings
(`git diff --name-only <that commit> HEAD`):

- a batch: a file that carries, or carried, `sr:invariant` or `sr:proves` for one of its
  invariants, or a `testdata/*.jsonl` beside one of its marked tests;
- the modules: a `module.yaml`, any file under `internal/`, or any Go file that is not a test;
- the rules: anything.

Launch the reviewers of a round together.

**Read-only.** A reviewer reads. It may copy the repository to a scratch directory and build
and run tests there. It changes nothing in the repository and commits nothing: you make every
fix yourself.

**Its answer.** A verdict for every invariant of its batch (or every module, or every rule),
and for each failure a concrete finding: the file and line, what it breaks, and what to do.

**Then.** Fix every finding of the round, commit, and start the next round.

Repeat until a round finds nothing: every batch, the modules and the rules each reviewed clean
at a commit after which none of their material changed. Only then is the work finished.
