#!/usr/bin/env bash
# subjects: ONE for the whole changeset when it adds or changes a module.yaml.
#   files        every module.yaml added or changed
#   fingerprint  what the judge compares: the concern, home and api of EVERY module, and the
#                files (and their content) every module's home globs match. A change to any
#                module, or a file landing in any home, judges the modules again, in one call.
# One call for all modules, not one per module: each per-module call re-read every other
# module, so the cost grew with the square of the module count for the same comparisons.
# Nothing here goes on without what it looked up: a path list or a home listing that cannot
# be worked out refuses (a subject silently left out is a set of modules nobody judges). The
# values that grow with the repo go to jq by file, never as one command-line argument.
set -uo pipefail
payload="$(cat)"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/changeset.sh"
slim_payload
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/modules.sh"
. "${SR_GUARDRAIL_DIR:-.}/../../_lib/subjects.sh"
load_modules
work="$(mktemp -d "${TMPDIR:-/tmp}/sr-subjects-module-distinct.XXXXXX")" || refuse_error "cannot make a directory for the subjects' work files"
trap 'rm -rf "$work"' EXIT
paths="$(changed_paths)" || refuse_error "the changed paths could not be listed, so the modules to judge cannot be worked out"
mpaths="$(grep '/module\.yaml$' <<<"$paths" || true)"
if [ -z "$mpaths" ]; then
  sub_finish unclaimed "[]"
  exit 0
fi
jq -c 'sort_by(.dir)' <<<"$MODULES" >"$work/modules" || refuse_error "the modules could not be listed"
: >"$work/homes"
while IFS= read -r m; do
  [ -n "$m" ] || continue
  module_home_files "$m" >>"$work/homes" || refuse_error "the files a module's home globs match could not be listed, so the subject cannot be keyed"
done < <(jq -c '.[]' "$work/modules")
printf '%s\n' "$mpaths" | sort -u >"$work/mpaths"
subs="$(jq -nc --rawfile p "$work/mpaths" --rawfile all "$work/modules" --rawfile h "$work/homes" \
  '[{id: "modules", files: ($p | split("\n") | map(select(. != ""))),
     extra: ("modules:" + $all + "\nhomes:" + ($h | sub("\n+$"; "")))}]')" ||
  refuse_error "could not build the subject of the changed modules"
sub_finish unclaimed "$subs"
