
The invariants are not listed here: find them. When the message that launched you names spec
files, your <invariant>s are exactly those. When it names none, they are every
`spec/*/invariants/*.yaml`. For each one:

- its `id` is `<domain>/<name>`, its domain folder and its file name:
  `spec/words/invariants/quotes-are-removed.yaml` is `words/quotes-are-removed`; its `spec`
  is that file;
- its <code> files are the files holding the marker line `// sr:invariant <id>`;
- its <test> files are the files holding the marker line `// sr:proves <id>`.

`git grep -n -E 'sr:(invariant|proves)[[:space:]]+<id>[[:space:]]*$'` lists both kinds for one
id, with their lines. Where this text speaks of a script that counts or reports markers: no
script runs here, and a missing marker is the business of the rule "Every invariant is marked
and proven", not of this section.
