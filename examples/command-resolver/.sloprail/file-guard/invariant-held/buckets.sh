#!/usr/bin/env bash
# The buckets this rule judges by. Source after changeset.sh.
#
# Every spec/<domain>/invariants/<id>.yaml of the committed tree, sorted by path, cut into
# runs of BUCKET_SIZE: b01 holds the first ten, b02 the next. Sorting by path keeps a domain's
# invariants together, and the same tree always gives the same buckets.
BUCKET_SIZE=10

# load_buckets — sets BUCKETS to a JSON array of {bucket, id, path}, one per invariant.
load_buckets() {
  BUCKETS="$( (cd "$SR_TREE" && ls spec/*/invariants/*.yaml 2>/dev/null) | LC_ALL=C sort |
    jq -Rnc --argjson n "$BUCKET_SIZE" '[inputs | select(length > 0)] | to_entries | map(
      {bucket: ("b" + (((.key / $n | floor) + 1 | tostring) | if length < 2 then "0" + . else . end)),
       path: .value,
       id: (.value | capture("^spec/(?<d>[^/]+)/invariants/(?<n>[^/]+)\\.yaml$") | "\(.d)/\(.n)")})')"
}

# markers_json KIND — prints every sr:<KIND> marker of the committed tree as [{p: path, q: id}].
markers_json() {
  load_markers "$1"
  printf '%s\n' "$MARKERS" | jq -Rnc '[inputs | select(length > 0) | split("\t") | {p: .[0], q: .[1]}]'
}
