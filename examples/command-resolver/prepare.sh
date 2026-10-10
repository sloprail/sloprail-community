#!/usr/bin/env bash
# Prepares the project a run starts from. sr-eval calls it as the fixture's setup script, in
# the project, after template/ (the seed) and this example's .sloprail/ are in place and
# before the first commit.
#
#   SR_EVAL_VARIANT=sloprail (default)   the template and the rules, as copied
#   SR_EVAL_VARIANT=bare                 the template alone: no rules, and nothing that names them
#
# Both variants get the same CLAUDE.md, spec/, config/ and adr/: the conventions are stated
# in both, and only one of them has anything checking them.
set -euo pipefail
variant="${SR_EVAL_VARIANT:-sloprail}"
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
  bare)
    rm -rf .sloprail
    # An ADR's `sloprails:` line names the rules that enforce it. There are none here.
    sed -i.bak '/^sloprails:/d' adr/*/ADR.md && rm -f adr/*/ADR.md.bak
    ;;
  *)
    echo "prepare: unknown SR_EVAL_VARIANT '$variant' (sloprail or bare)" >&2
    exit 1
    ;;
esac
[ -d .git ] && printf "%s\n" "$variant" > .git/sr-eval-variant || true
