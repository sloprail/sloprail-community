#!/usr/bin/env bash
set -euo pipefail
# spec-conflicts, the a10n way: changed invariants are clustered by the fields they mention and
# shown their neighbours (unchanged invariants sharing a field); pairs are reported on a judged
# side only, and a verdict is keyed on the invariant's own text.
# 1. two conflicting invariants on Variable.value, named far apart with 26 others on
#    Variable.name between them, are judged together and both refused.
# 2. a change to one of them alone is refused: the other is pulled in as a neighbour by the
#    shared field, ahead of the invariants sharing only the entity, and an invariant on another
#    entity is not; the neighbour is not judged.
# 3. once they agree, the spec passes.
# 4. editing one invariant re-judges it alone: the other, sharing its field, is not judged again.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-conflicts" "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/*/tests
# spec-quality is here for the speclib.py both share; it selects nothing in this case.
printf 'match: path matches "^-$"\nchecks:\n  - script: ./shape.py\n' > .sloprail/file-guard/spec-quality/file-guard.yaml
S=examples/demo/template/spec/v
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: name\n    type: string\n    doc: "Its name."\n  - name: value\n    type: string?\n    doc: "Its value at a point of the line."\n' > "$S/entities/Variable.yaml"
printf 'doc: "A function."\nfields:\n  - name: name\n    type: string\n    doc: "Its name."\n' > "$S/entities/Function.yaml"
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export PROMPT_LOG="$(mktemp)" OUT="$(mktemp)"
export SR_CHECKS_JUDGE_MOCKS=$(jq -nc --arg p "$SR_TEST_CASE_DIR/judge-mock.py" '{"file-guard/spec-conflicts/judge": $p}')
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { : > "$PROMPT_LOG"; sr-checks run --base "$1" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; echo "$1" >&2; exit 1; }
refused() { grep -qF "file-guard \"spec-conflicts\" $S/invariants/$1.yaml: refused" "$OUT"; }
judged() { awk '/^## The invariants to judge/{on=1} /^## Neighbours/{on=0} on' "$PROMPT_LOG" | grep -qF "<file path=\"$S/invariants/$1.yaml\">"; }
near() { awk '/^## Neighbours/{on=1} /^## Entities they cite/{on=0} on' "$PROMPT_LOG" | grep -qF "<file path=\"$S/invariants/$1.yaml\">"; }
inv() { printf 'predicate: >-\n  %s\nwhy: >-\n  %s\n' "$2" "A wrong value would be reported." > "$S/invariants/$1.yaml"; }
EMPTIES='Right after `unset NAME`, the {@ent:v:Variable} NAME has the empty string as its {@fld:v:Variable.value}.'
KEEPS='Right after `unset NAME`, the {@ent:v:Variable} NAME keeps the value it had as its {@fld:v:Variable.value}.'

# 1: the pair, 26 invariants apart
inv a-unset-empties "$EMPTIES"
for i in $(seq -w 1 26); do inv "m-filler-$i" "A {@ent:v:Variable} whose {@fld:v:Variable.name} is N$i is told apart from every other."; done
inv f-function "A {@fld:v:Function.name} names one function."
inv z-unset-keeps "$KEEPS"
commit pair
if run "$BASE"; then dump "1: two conflicting invariants on one field passed"; fi
refused a-unset-empties && refused z-unset-keeps || dump "1: the pair was not refused on both sides"
grep -qF "MOCK conflict on Variable.value" "$OUT" || dump "1: no refusal naming the conflict"

# 2: only z changes; a comes along as a neighbour
MID=$(git rev-parse HEAD)
inv z-unset-keeps "$KEEPS Always."
commit z-only
if run "$MID"; then dump "2: a changed invariant conflicting with an unchanged one passed"; fi
refused z-unset-keeps || dump "2: no refusal of z"
judged z-unset-keeps && near a-unset-empties || dump "2: a was not pulled in as a neighbour"
! judged a-unset-empties && ! refused a-unset-empties || dump "2: the neighbour was judged"
! near f-function || dump "2: an invariant on another entity was pulled in"
[ "$(awk '/^## Neighbours/{on=1} /^## Entities they cite/{on=0} on' "$PROMPT_LOG" | grep -c '^<file path=')" -le 29 ] || dump "2: more neighbours than the cap"

# 3: they agree
inv z-unset-keeps "$EMPTIES Always."
commit agree
run "$BASE" || dump "3: agreeing invariants were refused"

# 4: one edit, one judged
inv a-unset-empties "$EMPTIES Always."
commit a-only
run "$BASE" || dump "4: refused"
judged a-unset-empties || dump "4: the edited invariant was not judged"
! judged z-unset-keeps || dump "4: an unchanged invariant sharing its field was judged again"
