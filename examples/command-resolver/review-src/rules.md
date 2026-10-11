# Does the repository keep its six mechanical rules?

Six rules that need no judgement: each one either holds for the whole committed tree or names
the paths that break it. Check every rule over every file at `HEAD`, by reading and with
commands that change nothing (`git ls-files`, `git grep`, `git diff`, `wc -l`; `go list` in a
scratch copy).

How a glob in a `module.yaml` or in an ADR's front matter matches a path: `*` and `**` both
match any run of characters, `/` included, and a glob also matches a directory when it matches
the directory's path followed by `/` (`internal/words/**` matches `internal/words` and
everything under it). A module is a tracked `module.yaml`; its directory names it.

## Rule 1: what was given is unchanged

Nothing under `spec/`, `config/`, `adr/` or `review/`, nor `CLAUDE.md`, is added, changed or
removed. Compare with the repository's first commit:

```
git diff --name-status "$(git rev-list --max-parents=0 HEAD)" HEAD -- spec config adr review CLAUDE.md
```

**Pass**: it prints nothing. **Fail**: every path it prints. What to do: restore the file to
what it was in the first commit, and change the code or its tests so they meet the invariants
and the ADRs as written. An invariant that looks wrong, or two that contradict each other,
stay as they are and are reported by the author at the end.

## Rule 2: every file is in a declared place

The path of every tracked file (`git ls-files`, relative to the repository root) is matched in
full by one of these regular expressions:

@PLACES@
- `^review/[a-z0-9-]+\.md$`

**Pass**: every path matches one. **Fail**: every path that matches none. What to do: move the
file to a declared place (`adr/file-placement/ADR.md` says what each place is for) or remove it.

## Rule 3: Go files stay small

- A file whose name ends in `_test.go` holds at most @LIMIT_GO_TEST@ lines.
- Every other file whose name ends in `.go` holds at most @LIMIT_GO@ lines.

These are `limits.go_test` and `limits.go` in the front matter of `adr/file-size/ADR.md`. A
path listed under `ceilings:` there is held to the number given for it instead of the limit.
Lines are counted as `awk 'END { print NR }'` counts them: a last line with no newline is a
line. The rule covers every tracked `.go` file, wherever it is.

**Pass**: no file is over. **Fail**: every file over, with its line count and its limit. What
to do: split it by responsibility into smaller files; a test that lists variations moves them
into a case file (`testdata/<name>.jsonl`) and loops over it.

## Rule 4: every invariant is marked and proven

An invariant is a file `spec/<domain>/invariants/<name>.yaml`; its id is `<domain>/<name>`. A
marker is a whole line: optional indentation, a comment leader (`//`, `#` or `--`),
`sr:invariant` or `sr:proves`, the id as one token, and nothing after it. This lists every
marker of one kind in the tracked text files:

```
git grep -n -I -E '^[[:space:]]*(//|#|--)[[:space:]]*sr:invariant[[:space:]]+("[^"]*"|[^[:space:]"][^[:space:]]*)[[:space:]]*$'
```

(the same with `sr:proves`). A line that carries anything else beside the marker is not a
marker. A test is a file whose path ends in `_test.go` or starts with `tests/`.

For every invariant in `spec/`:

- at least one `sr:invariant <id>` marker stands in a file that is not a test;
- at least one `sr:proves <id>` marker stands in a test;
- `<domain>` and `<name>` are kebab-case (`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`).

And for every marker whose id has the shape `<domain>/<name>` (`^[a-z0-9-]+/[a-z0-9-]+$`):

- the id names an invariant file that exists;
- an `sr:invariant` marker is not in a test, and an `sr:proves` marker is in a test.

**Pass**: all of it holds. **Fail**: every invariant with no marked code, every invariant with
no marked test, every marker that names no invariant, and every marker on the wrong side.
Whether the marked code is right and the marked tests are enough is not this rule's question.

## Rule 5: every Go file under the module space belongs to exactly one module

The space is `space: @SPACE@` and the exceptions are `exceptions: @EXCEPTIONS@`, both from the
front matter of `adr/modules-cover-code/ADR.md`.

- Every `module.yaml` is valid YAML and has a `concern:` that is not empty.
- Every tracked Go file that is not a test (`git ls-files -- '*.go' ':!*_test.go'`), that a
  `space` glob matches and that no `exceptions` glob matches, is matched by the `home` globs
  of exactly one module.
- The exceptions do not grow, and no Go file is added under one.

**Pass**: all of it holds. **Fail**: every file that belongs to no module (what to do: put it
in a module's home, or add a `module.yaml` for it), every file in more than one module's home,
with those modules (module homes may not overlap), and every module with no concern.

## Rule 6: a module is imported only through its api

In a scratch copy, list every package of the repository with what it imports:

```
go list -f '{{.ImportPath}}{{range .Imports}} {{.}}{{end}}' ./...
```

Take each package and each import that is inside this repository's own Go module, as a
directory path relative to the repository root. For every module (a `module.yaml`): a package
whose directory no `home` glob of the module matches must not import a package whose directory
a `home` glob does match, unless that directory is written out, exactly, in the module's
`api:` list. Imports made only by test files are not in this listing and are not checked.
With no `go.mod` or no `module.yaml` there is nothing to check.

**Pass**: no such import. **Fail**: every one, as `<importer> imports <imported>, inside module
<dir> but not its api`. What to do: import the module through a package its `api:` lists.

## Your reasoning

Pass or fail, one line per rule: the rule, its verdict, and what you ran or read to decide it.
On a fail, list every offending path under that line. A verdict with no account of how it was
checked is not a pass.
