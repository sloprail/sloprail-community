No search has been run and no list of matches prepared: make each module's list yourself. A
module is a `module.yaml` in the repository (`git ls-files '*module.yaml'`). For each one,
`dir` is the directory holding it, and <concern>, `home` and `api` are its `concern:`, `home:`
and `api:` values.

A module's matches are the lines that look like its own logic and sit outside its home.
Search every tracked Go file that is not a test (`*_test.go`) and that none of the module's
`home` globs matches (`*` and `**` both match across `/`) for the work its concern names: the
names, literals and patterns its own code is built from. When an executable `candidates.sh`
sits beside the `module.yaml`, run it from the root of a scratch copy instead: it prints the
module's candidates, one `path:line:snippet` per line, and you drop those inside the home and
those in tests. Drop, too, every path listed under `exceptions:` in the front matter of an
`adr/*/ADR.md`. What is left is the module's list (the "file" this text speaks of), and
`count` is its length. A module with nothing left has nothing to classify: say so in one line.
