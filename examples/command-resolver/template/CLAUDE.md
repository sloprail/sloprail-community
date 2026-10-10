# Command resolver

A command-line tool that reads one shell command line and reports every program
that line would run, without running anything.

## The specification

`spec/` is the whole definition of what the tool does, and it is fixed: never
add, change or remove a file under it. `config/`, `adr/` and this file are fixed too.

- `spec/<domain>/entities/<Entity>.yaml` names the things the tool talks about
  and their fields.
- `spec/<domain>/invariants/<id>.yaml` each state one rule that must always hold
  (`predicate`) and what goes wrong without it (`why`). `{@fld:domain:Entity.field}`
  and `{@ent:domain:Entity}` in a predicate point at an entity file.
- `config/builtin.yaml` is the built-in table of programs the tool looks through.

The tool is finished when every invariant holds. There is no other description
of its behaviour: where the spec is silent, the tool does the least that keeps
every invariant true.

## The tool

```
resolve [--config FILE] < line
```

- The whole of standard input is the line (`Line.text`).
- The tool's own environment and working directory are the `Context`.
- `--config FILE` adds a user's table, in the shape of `config/builtin.yaml`.
- It prints one JSON object, a `Resolution`, whose keys are the field names in the
  spec. A field the spec calls absent is left out.
- It exits 0 for every line, valid shell or not, and never executes any part of it.

## How this repository is built

Each of these is a decision in `adr/`. Read the ADR before writing code it covers.

- **Every invariant is marked** ([adr/invariants-are-proven](adr/invariants-are-proven/ADR.md)).
  The code that upholds an invariant carries `// sr:invariant <domain>/<id>`; a
  test that proves it carries `// sr:proves <domain>/<id>`. Every invariant has
  both, the code does what the predicate says, and the tests would fail if it
  did not.
- **Code lives in modules** ([adr/modules-cover-code](adr/modules-cover-code/ADR.md)).
  Every Go file under `internal/` belongs to exactly one module, declared by a
  `module.yaml` beside it:

  ```yaml
  concern: one sentence naming the one responsibility of this module
  home: ["internal/words/**"]        # the files it owns
  api: ["internal/words"]            # the packages other modules may import
  ```

  No two modules share a concern, a module holds only code of its concern, and
  a module is imported only through its `api`. Logic that exists in one module
  is used from there, never copied into another.
- **Files are small** ([adr/file-size](adr/file-size/ADR.md)). A Go file has at
  most 150 lines, a test file at most 400. Split by responsibility.
- **Every file has a declared place** ([adr/file-placement](adr/file-placement/ADR.md)).
  `cmd/resolve/` holds only the entry point; everything else is under `internal/`.

## Building

Go. `mvdan.cc/sh/v3` may be used for parsing. Build with `go build ./cmd/resolve`,
test with `go test ./...`. Commit your work as you go.
