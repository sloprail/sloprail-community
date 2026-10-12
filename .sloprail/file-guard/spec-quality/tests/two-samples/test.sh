#!/usr/bin/env bash
set -euo pipefail
# The judge is asked twice per file, as two independent samples; a file is refused only for a
# material finding (a concrete input inside the boundary, two readings, two different outputs),
# and when either sample gives one. Every other failing item is a note and does not block.
# 1. a clean file is judged by two samples and passes.
# 2. a material finding in both samples refuses the file, quoting the input.
# 3. a material finding in the second sample only still refuses the file.
# 4. a failing item without a material finding, or with two equal outputs, is a note: it passes.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard .claude/skills
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/spec-quality/tests
cp -R "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-invariant" "$SR_TEST_SLOPRAIL_DIR/../.claude/skills/document-entity" .claude/skills/
S=examples/demo/template/spec/v
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line."\n' > "$S/entities/Variable.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)" OUT="$(mktemp)" CALLS="$(mktemp -d)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.py" '{"file-guard/spec-quality/judge": $p}')
dump() { cat "$OUT" >&2; echo "$1" >&2; exit 1; }
refused() { grep -qF "file-guard \"spec-quality\" $S/invariants/$1.yaml: refused" "$OUT"; }
for n in clean MATERIAL SECOND NOTE SAME; do
  printf 'predicate: >-\n  %s: the {@fld:v:Variable.value} is set.\nwhy: >-\n  A wrong value would be reported.\n' "$n" > "$S/invariants/$n.yaml"
done
git add -A && git -c user.name=t -c user.email=t@t commit -q -m five
: > "$SR_EVENTS_FILE"
if sr-checks run --base "$BASE" --head HEAD >"$OUT" 2>&1; then dump "2: a material finding passed"; fi
[ "$(cat "$CALLS/${S//\//_}_invariants_clean.yaml")" = xx ] || dump "1: the clean file was not judged by two samples"
! refused clean || dump "1: the clean file was refused"
refused MATERIAL && grep -qF -- '- concrete: MOCK material Input: cd /a' "$OUT" || dump "2: the material finding did not refuse, quoting its input"
refused SECOND || dump "3: a material finding of the second sample only did not refuse"
! refused NOTE || dump "4: a failing item without a material finding blocked"
! refused SAME || dump "4: a material finding with two equal outputs blocked"
