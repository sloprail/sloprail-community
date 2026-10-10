# Command resolver

A command-line tool that reads one shell command line and reports every program
that line would run, without running anything.

- `spec/<domain>/entities/<Entity>.yaml` names the things the tool talks about and
  their fields. `spec/<domain>/invariants/<id>.yaml` each state one rule that must
  always hold (`predicate`) and what goes wrong without it (`why`). Together they
  are the specification.
- `config/builtin.yaml` is the built-in table of programs the tool looks through.

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

## Building

Go. `mvdan.cc/sh/v3` may be used for parsing. Build with `go build ./cmd/resolve`,
test with `go test ./...`.
