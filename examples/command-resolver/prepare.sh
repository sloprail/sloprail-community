#!/usr/bin/env bash
# Prepares the project a run starts from. sr-eval calls it as the fixture's setup script, in
# the project, after template/ (the seed) and this example's .sloprail/ are in place and
# before the first commit.
#
#   SR_EVAL_VARIANT=sloprail (default)   the template and the rules, as copied
#   SR_EVAL_VARIANT=bare                 the template alone: no rules, and nothing that names them
#   SR_EVAL_VARIANT=review-whole         bare, and the builder has one reviewer read everything, round after round, until it finds nothing
#   SR_EVAL_VARIANT=review-batched       bare, and one reviewer per batch of ten invariants, one for the modules, one for the mechanical rules, until all are clean
#   SR_EVAL_VARIANT=review-once          bare, and one reviewer reads everything once; its findings are fixed and that is all
#
# sloprail and bare get the same CLAUDE.md, spec/, config/ and adr/: the conventions are stated
# in both, and only one of them has anything checking them. A review variant is bare plus two
# things: review/, the instructions its reviewers are handed, and a last section of CLAUDE.md
# that tells the builder when to launch them and when to stop. Reviewers are sub-agents of the
# builder; nothing outside the session checks anything.
set -euo pipefail
variant="${SR_EVAL_VARIANT:-sloprail}"
# This example, where the script is: the rules and review-src/ are read from here. A project
# prepared without the rules has no .sloprail/ of its own to read them from.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/review-src"
rules="$here/.sloprail"

die() { echo "prepare: $1" >&2; exit 1; }

# rubric TEMPLATE FIND — a judge's rubric, word for word: TEMPLATE without its one block of
# template plumbing (every line from the first that holds {% to the last), and FIND in its
# place: the plain words that tell a reviewer how to find the same material itself.
rubric() {
  awk -v find="$2" '
    NR == FNR { if (index($0, "{%")) { if (!first) first = FNR; last = FNR } next }
    !first { print FILENAME ": no template block to replace" > "/dev/stderr"; bad = 1; exit }
    FNR == first { while ((getline line < find) > 0) { print line; n++ } }
    FNR >= first && FNR <= last { next }
    index($0, "{{") || index($0, "{%") { print FILENAME ":" FNR ": template syntax outside its block" > "/dev/stderr"; bad = 1; exit }
    { print }
    END { exit (bad || !n) }' "$1" "$1"
}

# front FILE KEY — the value of the front-matter line `KEY: value` of FILE, at any depth,
# without a trailing comment.
front() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside { line = $0; sub(/^[[:space:]]+/, "", line)
      if (index(line, k ":") == 1) {
        v = substr(line, length(k) + 2); sub(/[[:space:]]+#.*$/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v; found = 1; exit } }
    END { exit !found }' "$1"
}

# places — the path patterns of file-guard/structure.yaml, one Markdown bullet each. The
# rules' own folder is not a place in a project that has none. A line that is neither a
# comment nor a pattern stops the script: it would be a place this list silently lost.
places() {
  awk '
    /^[[:space:]]*(#.*)?$/ || /^allow:$/ { next }
    /^  - glob: "\.sloprail\/\*\*"$/ { next }
    /^  - regex: \047.*\047$/ { print "- `" substr($0, 13, length($0) - 13) "`"; n++; next }
    { print FILENAME ":" FNR ": not a pattern this script can list: " $0 > "/dev/stderr"; bad = 1; exit }
    END { exit (bad || !n) }' "$rules/file-guard/structure.yaml"
}

# fill FILE — FILE with every @NAME@ replaced by the value of the variable REVIEW_NAME.
fill() {
  awk '
    { while (match($0, /@[A-Z_]+@/)) {
        k = "REVIEW_" substr($0, RSTART + 1, RLENGTH - 2)
        if (!(k in ENVIRON)) { print FILENAME ":" FNR ": no value for " k > "/dev/stderr"; bad = 1; exit }
        $0 = substr($0, 1, RSTART - 1) ENVIRON[k] substr($0, RSTART + RLENGTH) }
      print }
    END { exit bad }' "$1"
}

# The four things a review covers. The first three are the judges' rubrics; the fourth states
# what the rules' scripts enforce, with its numbers and patterns read from where the scripts
# read them.
part_invariants() { rubric "$rules/file-guard/invariant-held/code-and-tests-hold.md.j2" "$src/invariants.find.md"; }
part_concerns() { rubric "$rules/file-guard/module-distinct/distinct-concern.md.j2" "$src/modules-distinct.find.md"; }
part_leaks() { rubric "$rules/file-guard/module-leaks/leak-or-use.md.j2" "$src/modules-leaks.find.md"; }
part_rules() { fill "$src/rules.md"; }

# page FILE PART… — one reviewer's instructions: who it is, the parts it covers, how it answers.
page() {
  local f="$1" p
  shift
  {
    cat "$src/head.md"
    for p in "$@"; do
      printf '\n---\n\n'
      "part_$p" || die "the $p part of $f could not be written"
    done
    printf '\n---\n\n'
    cat "$src/answer.md"
  } > "$f"
}

# review — review/ and the last section of CLAUDE.md, for the review variant being prepared.
review() {
  REVIEW_LIMIT_GO="$(front adr/file-size/ADR.md go)" || die "adr/file-size/ADR.md states no limits.go"
  REVIEW_LIMIT_GO_TEST="$(front adr/file-size/ADR.md go_test)" || die "adr/file-size/ADR.md states no limits.go_test"
  REVIEW_SPACE="$(front adr/modules-cover-code/ADR.md space)" || die "adr/modules-cover-code/ADR.md states no space"
  REVIEW_EXCEPTIONS="$(front adr/modules-cover-code/ADR.md exceptions)" || die "adr/modules-cover-code/ADR.md states no exceptions"
  REVIEW_PLACES="$(places)" || die "the places of file-guard/structure.yaml could not be listed"
  REVIEW_BATCH_SIZE="$(sed -n 's/^BUCKET_SIZE=\([0-9][0-9]*\)$/\1/p' "$rules/file-guard/invariant-held/buckets.sh")"
  [ -n "$REVIEW_BATCH_SIZE" ] || die "file-guard/invariant-held/buckets.sh states no BUCKET_SIZE"
  export REVIEW_LIMIT_GO REVIEW_LIMIT_GO_TEST REVIEW_SPACE REVIEW_EXCEPTIONS REVIEW_PLACES REVIEW_BATCH_SIZE
  mkdir review
  case "$variant" in
    review-batched)
      page review/invariants.md invariants
      page review/modules.md concerns leaks
      page review/rules.md rules
      ;;
    *) page review/review.md invariants concerns leaks rules ;;
  esac
  { printf '\n'; fill "$src/claude-$variant.md"; } >> CLAUDE.md || die "the review section of CLAUDE.md could not be written"
}

# The rules' own test cases are for whoever changes the rules, not for the run.
find .sloprail -depth \( -name tests -o -name structure.tests \) -type d -exec rm -r {} + 2>/dev/null || true
case "$variant" in
  sloprail)
    command -v yq >/dev/null 2>&1 || echo "prepare: yq is not on PATH yet; the fixture runs freshMachine, so the plugin's install.sh puts it there at session start" >&2
    # A file-guard judges commits, and a Stop only verifies the ranges the session tracks:
    # nothing is tracked unless SR_AUTO_WATCH_GIT_REFS=1. With it the session tracks its own
    # branch, so a Stop is refused until `sr-checks run` has judged the work and it passed.
    # Set in the project's settings, the way a project that wants this would set it.
    mkdir -p .claude
    [ -f .claude/settings.json ] || echo '{}' > .claude/settings.json
    jq '.env = ((.env // {}) + {SR_AUTO_WATCH_GIT_REFS: "1"})' .claude/settings.json > .claude/settings.json.tmp
    mv .claude/settings.json.tmp .claude/settings.json
    ;;
  bare | review-whole | review-batched | review-once)
    rm -rf .sloprail
    # An ADR's `sloprails:` line names the rules that enforce it. There are none here.
    sed -i.bak '/^sloprails:/d' adr/*/ADR.md && rm -f adr/*/ADR.md.bak
    if [ "$variant" != bare ]; then review; fi
    ;;
  *)
    echo "prepare: unknown SR_EVAL_VARIANT '$variant' (sloprail, bare, review-whole, review-batched or review-once)" >&2
    exit 1
    ;;
esac
[ -d .git ] && printf "%s\n" "$variant" > .git/sr-eval-variant || true
