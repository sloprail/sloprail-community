The modules are not listed here: find them. A module is a `module.yaml` in the repository
(`git ls-files '*module.yaml'`). For each one, the <module> this text speaks of is:

- `dir`: the directory holding the `module.yaml`;
- <concern> and `api`: its `concern:` and `api:` values;
- `changed`: "true" for every module. All of them are reviewed, each against every other;
- one <home> for each glob in its `home:` list. No list of files has been prepared: make it
  yourself. A glob's files are the tracked files (`git ls-files`) it matches, where `*` and
  `**` both match across `/`, and `count` is how many there are. That list is the "file" the
  paragraph above tells you to read.
