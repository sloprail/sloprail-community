#!/usr/bin/env bash
# The whole example, cut down to the closed slice in slice.txt: prepare.sh as for eval/build,
# then every invariant not listed there is removed before the first commit. Entities, config/
# and adr/ stay whole. The agent sees only the slice's invariants; CLAUDE.md, the prompt, the
# rules and the score are eval/build's.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
"$here/../../prepare.sh"
keep="$(grep -v '^#' "$here/slice.txt")"
want="$(printf '%s\n' "$keep" | grep -c .)"
for f in spec/*/invariants/*.yaml; do
  d="${f#spec/}"; id="${d%%/*}/$(basename "$f" .yaml)"
  printf '%s\n' "$keep" | grep -Fxq -- "$id" || rm "$f"
done
n="$(ls spec/*/invariants/*.yaml | wc -l)"
[ "$n" -eq "$want" ] || { echo "setup: expected $want invariants, kept $n" >&2; exit 1; }
