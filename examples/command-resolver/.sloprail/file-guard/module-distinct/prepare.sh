#!/usr/bin/env bash
# prepare: every module with its concern, home and api, whether this changeset added or changed
# it, and for each of its home globs the files it matches, one path per line in a file outside
# the project (nothing that can grow is put in the prompt).
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/modules.sh"
load_modules
# every lookup refuses when it fails: a failed one must not become "no module" (skip) or a module
# with no home files
changed="$(cs '[.changeset.files[].path | select(endswith("/module.yaml")) | rtrimstr("/module.yaml")] | unique')" ||
  refuse_error "the changed module.yaml files could not be worked out"
[ "$(jq 'length' <<<"$MODULES")" -gt 0 ] || { jq -n '{skip: true}'; exit 0; }
work="$(mktemp -d "${TMPDIR:-/tmp}/sr-judge-module-distinct.XXXXXX")" || refuse_error "cannot make a directory for the judge's files"
: >"$work/modules.jsonl"
k=0
while IFS= read -r m; do
  [ -n "$m" ] || continue
  k=$((k + 1))
  dir="$(jq -r '.dir' <<<"$m")" || refuse_error "could not read a module's directory"
  module_home_files "$m" >"$work/m$k.all" || refuse_error "the files the home globs of $dir match could not be listed"
  globs="$(jq -r '.home[]' <<<"$m")" || refuse_error "could not read the home globs of $dir"
  homes="[]"; i=0
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    i=$((i + 1))
    awk -F'\t' -v g="$g" '$1 == g {print $2}' "$work/m$k.all" | sort -u >"$work/m$k-home-$i.files" || refuse_error "could not list the files the home glob $g matches"
    n="$(grep -c . "$work/m$k-home-$i.files")"   # 1 (and "0") when it matches nothing
    homes="$(jq -c --arg g "$g" --arg f "$work/m$k-home-$i.files" --argjson n "${n:-0}" '. + [{glob: $g, files: $f, count: $n}]' <<<"$homes")" ||
      refuse_error "could not record the files the home glob $g matches"
  done <<<"$globs"
  jq -c --argjson h "$homes" --argjson c "$changed" '. + {homes: $h, changed: (.dir as $d | $c | index($d) != null)}' <<<"$m" >>"$work/modules.jsonl" ||
    refuse_error "could not build the module $dir for the judge"
done < <(jq -c 'sort_by(.dir) | .[]' <<<"$MODULES")
jq -n -c --slurpfile m "$work/modules.jsonl" '{additionalContext: {modules: $m}}' || refuse_error "could not build the judge's context"
