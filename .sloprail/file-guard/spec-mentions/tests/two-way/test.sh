#!/usr/bin/env bash
set -euo pipefail
# spec-mentions checks the whole spec at head on any change to it, so it holds both ways: a new
# invariant with a broken mention, and an unchanged invariant whose mention an entity change
# broke, are refused alike.
# 1. a spec whose mentions all resolve passes.
# 2. a new invariant naming an undeclared field is refused.
# 3. a new invariant with no typed mention is refused; one naming an entity in plain words is
#    refused with the token to write; one reading a field by its bare name (`whose cwd`) where it
#    mentions only the entity is refused with the field's token.
# 4. renaming a field an unchanged invariant mentions is refused, naming that invariant.
# 5. deleting an entity file an unchanged invariant mentions is refused.
# 6. renaming an entity file (git mv) an unchanged invariant mentions is refused.
# 7. deleting an invariant runs the check again, and a sound spec passes.
rm -rf .sloprail .claude; git init -q .
export PYTHONDONTWRITEBYTECODE=1
printf '__pycache__/\n' > .gitignore
mkdir -p .sloprail/file-guard
cp -R "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-mentions" "$SR_TEST_SLOPRAIL_DIR/file-guard/spec-quality" .sloprail/file-guard/
rm -rf .sloprail/file-guard/*/tests
# spec-quality is here for the speclib.py both share; it selects nothing in this case.
printf 'match: path matches "^-$"\nchecks:\n  - script: ./shape.py\n' > .sloprail/file-guard/spec-quality/file-guard.yaml
S=examples/demo/template/spec/sh
mkdir -p "$S/entities" "$S/invariants"
printf 'doc: "A shell variable."\nfields:\n  - name: name\n    type: string\n    doc: "Its name."\n  - name: value\n    type: string?\n    doc: "Its value."\n' > "$S/entities/Variable.yaml"
printf 'doc: "What a shell knows at one point."\nfields:\n  - name: cwd\n    type: string?\n    doc: "The working directory there."\n' > "$S/entities/Scope.yaml"
inv() { printf 'predicate: >-\n  %s\nwhy: >-\n  A wrong answer would be reported.\n' "$2" > "$S/invariants/$1.yaml"; }
inv unset-empties 'After `unset NAME`, the {@fld:sh:Variable.value} of NAME is empty.'
inv cd-moves 'After `cd DIR`, the {@fld:sh:Scope.cwd} is DIR.'
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
BASE=$(git rev-parse HEAD)
SETUP=$(sr-test agent "$SR_TEST_CASE_DIR/agent.sh" --prompt "set up")
while IFS= read -r kv; do export "$kv"; done < <(echo "$SETUP" | jq -er ".env[]")
export OUT="$(mktemp)"
commit() { git add -A && git -c user.name=t -c user.email=t@t commit -q -m "$1"; }
run() { sr-checks run --base "$(git rev-parse HEAD^)" --head HEAD >"$OUT" 2>&1; }
dump() { cat "$OUT" >&2; echo "$1" >&2; exit 1; }
says() { grep -qF -- "$1" "$OUT"; }
reset() { git reset -q --hard "$BASE"; }

# 1
inv export-marks 'After `export NAME`, the {@ent:sh:Variable} NAME is exported.'
commit sound
run || dump "1: a sound spec was refused"
says 'file-guard "spec-mentions"' || dump "1: the check did not run"

# 2
reset; inv typo 'After `NAME=v`, the {@fld:sh:Variable.valu} of NAME is v.'
commit typo
if run; then dump "2: an undeclared field passed"; fi
says "$S/invariants/typo.yaml: {@fld:sh:Variable.valu} names a field" || dump "2: no refusal naming the undeclared field"

# 3
reset; inv bare 'After `NAME=v`, the value of NAME is v.'
commit bare
if run; then dump "3: an invariant with no mention passed"; fi
says "$S/invariants/bare.yaml: the predicate names no" || dump "3: no refusal of the bare invariant"
reset; inv plain 'After `cd DIR`, the Scope.cwd is DIR, as the {@ent:sh:Scope} keeps it.'
commit plain
if run; then dump "3: a plain entity name passed"; fi
says '`Scope.cwd` names a modelled thing in plain words; write {@ent:sh:Scope} or {@fld:sh:Scope.cwd}' || dump "3: no refusal with the token to write"
reset; inv loose 'After `cd DIR`, the {@ent:sh:Scope} whose cwd was DIR before keeps it.'
commit loose
if run; then dump "3: a field read by its bare name passed"; fi
says '`whose cwd` reads a field the predicate never mentions; write {@fld:sh:Scope.cwd}' || dump "3: no refusal naming the field's token"

# 4
reset; sed -i 's/name: value/name: content/' "$S/entities/Variable.yaml"
commit rename-field
if run; then dump "4: a field rename that broke an invariant passed"; fi
says "$S/invariants/unset-empties.yaml: {@fld:sh:Variable.value} names a field" || dump "4: the unchanged invariant was not named"

# 5
reset; git rm -q "$S/entities/Scope.yaml"
commit delete-entity
if run; then dump "5: deleting a mentioned entity passed"; fi
says "$S/invariants/cd-moves.yaml: {@fld:sh:Scope.cwd} names an entity with no" || dump "5: the unchanged invariant was not named"

# 6
reset; git mv "$S/entities/Scope.yaml" "$S/entities/Place.yaml"
commit rename-entity
if run; then dump "6: renaming a mentioned entity passed"; fi
says "$S/invariants/cd-moves.yaml: {@fld:sh:Scope.cwd} names an entity with no" || dump "6: the unchanged invariant was not named"

# 7
reset; git rm -q "$S/invariants/cd-moves.yaml"
commit delete-invariant
run || dump "7: a sound spec was refused after deleting an invariant"
says 'file-guard "spec-mentions"' || dump "7: the check did not run on a deletion"
