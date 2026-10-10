#!/usr/bin/env bash
# The whole example, cut down to 12 invariants: prepare.sh as for eval/build, then every
# invariant not listed here is removed before the first commit. Entities, config/ and adr/
# stay whole. Twelve is two judge buckets (10 + 2) across two domains, enough for every rule
# to have something to refuse.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
"$here/../../prepare.sh"
keep="
line/argv-holds-every-word-in-order
line/bin-is-the-basename
line/every-command-is-reported
line/invalid-line-yields-a-parse-error
line/nothing-is-executed
line/valid-line-has-no-parse-error
words/context-variable-resolves
words/glob-word-is-unknown
words/quoted-whitespace-does-not-split
words/quotes-are-removed
words/unknown-is-set-exactly-without-a-value
words/unset-variable-is-empty
"
for f in spec/*/invariants/*.yaml; do
  d="${f#spec/}"; id="${d%%/*}/$(basename "$f" .yaml)"
  printf '%s' "$keep" | grep -Fxq -- "$id" || rm "$f"
done
n="$(ls spec/*/invariants/*.yaml | wc -l)"
[ "$n" -eq 12 ] || { echo "setup: expected 12 invariants, kept $n" >&2; exit 1; }
