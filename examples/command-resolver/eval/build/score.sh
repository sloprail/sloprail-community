#!/bin/sh
# What can be scored from the repository alone: the tool builds, its own tests pass, the spec
# is untouched, and how many invariants carry both markers. Whether the tool is CORRECT is
# the hidden scorecard's (lines and their expected Resolution, kept outside this repository
# so no run can read it): SR_EVAL_SCORECARD names its runner when there is one.
set -u
P="${SR_EVAL_PROJECT_DIR:?SR_EVAL_PROJECT_DIR not set}"
cd "$P" || exit 2
fail=0
row() { printf '%-28s %s\n' "$1" "$2"; }

if go build -o "$P/.git/resolve" ./cmd/resolve >/dev/null 2>&1; then row "builds" yes; else row "builds" NO; fail=1; fi
if go test ./... >/dev/null 2>&1; then row "own tests pass" yes; else row "own tests pass" NO; fail=1; fi
if [ -z "$(git status --porcelain)" ]; then row "everything committed" yes; else row "everything committed" NO; fail=1; fi
if git diff --quiet "${SR_EVAL_SEED_COMMIT:-HEAD}" HEAD -- spec; then row "spec untouched" yes; else row "spec untouched" NO; fail=1; fi

total=0; both=0
for f in spec/*/invariants/*.yaml; do
  [ -f "$f" ] || continue
  total=$((total + 1))
  d="${f#spec/}"; id="${d%%/*}/$(basename "$f" .yaml)"
  git grep -q -E "^[[:space:]]*//[[:space:]]*sr:invariant[[:space:]]+$id[[:space:]]*$" -- '*.go' ':!*_test.go' 2>/dev/null &&
    git grep -q -E "^[[:space:]]*//[[:space:]]*sr:proves[[:space:]]+$id[[:space:]]*$" -- '*_test.go' 2>/dev/null &&
    both=$((both + 1))
done
row "invariants with both markers" "$both / $total"
row "variant" "$(cat .git/sr-eval-variant 2>/dev/null || echo unknown)"

if [ -n "${SR_EVAL_SCORECARD:-}" ]; then
  "$SR_EVAL_SCORECARD" "$P/.git/resolve" || fail=1
else
  row "scorecard" "not run (SR_EVAL_SCORECARD not set)"
fi
exit "$fail"
