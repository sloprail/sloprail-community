## Review before you finish

`review/` is given and fixed, like `spec/`: never add, change or remove a file under it.

The work is reviewed once before it is finished.

1. **When.** Once everything is implemented, `go build ./cmd/resolve` and `go test ./...` pass
   and everything is committed, launch one reviewer.
2. **Who.** The reviewer is a sub-agent you launch, running the same model as yours at the
   same reasoning effort as yours.
3. **Its instructions.** The full text of `review/review.md`, word for word, with nothing
   added, removed or summarised. It reviews the whole repository.
4. **Read-only.** A reviewer reads. It may copy the repository to a scratch directory and
   build and run tests there. It changes nothing in the repository and commits nothing: you
   make every fix yourself.
5. **Its answer.** A verdict for every invariant, every module and every rule, and for each
   failure a concrete finding: the file and line, what it breaks, and what to do.
6. **Then.** Fix every finding, make the build and the tests pass again, and commit.

That is the one review: do not launch a second. The work is finished when its findings are
fixed and committed.
