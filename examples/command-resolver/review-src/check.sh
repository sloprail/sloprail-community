#!/usr/bin/env bash
# Checks what ../prepare.sh makes of the three review variants, without running any agent:
#
#   1. a review variant is the bare project plus review/ and one last section of CLAUDE.md,
#      and nothing else differs;
#   2. every judge's rubric stands in review/ word for word: the judge template, with its
#      block of template plumbing (the lines from the first {% to the last) swapped for the
#      *.find.md beside this script, is one unbroken run of lines of the reviewer's file;
#   3. neither review/ nor the CLAUDE.md section names the rules, a judge, a run or another
#      way the project could have been prepared.
#
# Run it after changing a judge template, a file here or prepare.sh:  review-src/check.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ex="$(dirname "$here")"
work="$(mktemp -d "${TMPDIR:-/tmp}/review-check.XXXXXX")" || exit 2
trap 'rm -rf "$work"' EXIT
fails=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# project VARIANT — a project the way the fixture makes one for a variant without the rules:
# the seed, a repository, the setup script.
project() {
  mkdir "$work/$1" && cp -a "$ex/template/." "$work/$1/" && git -C "$work/$1" init --quiet &&
    (cd "$work/$1" && SR_EVAL_VARIANT="$1" "$ex/prepare.sh") >"$work/$1.log" 2>&1
}

# expected TEMPLATE FIND — the rubric as it must stand in a reviewer's file. Written apart from
# prepare.sh's own rendering on purpose: line numbers from grep, the cut by sed.
expected() {
  local first last
  first="$(grep -n -F '{%' "$1" | head -n 1 | cut -d: -f1)"
  last="$(grep -n -F '{%' "$1" | tail -n 1 | cut -d: -f1)"
  [ -n "$first" ] || return 1
  sed -n "1,$((first - 1))p" "$1"
  cat "$2"
  sed -n "$((last + 1)),\$p" "$1"
}

# holds FILE WANT — the lines of WANT are one unbroken run of lines of FILE, starting where
# WANT's first line (a rubric's title, which stands once) is found.
holds() {
  local at n
  at="$(grep -n -x -F -- "$(head -n 1 "$2")" "$1" | cut -d: -f1)"
  case "$at" in '' | *[!0-9]*) return 1 ;; esac
  n="$(wc -l < "$2")"
  sed -n "${at},$((at + n - 1))p" "$1" | diff -u "$2" - >"$work/diff" 2>&1
}

project bare || { cat "$work/bare.log"; echo "check: prepare.sh failed for bare" >&2; exit 2; }
rules="$ex/.sloprail/file-guard"
for v in review-whole review-batched review-once; do
  if project "$v"; then ok "$v: prepare.sh exits 0"; else bad "$v: prepare.sh failed: $(cat "$work/$v.log")"; continue; fi
  p="$work/$v"

  # 1. bare, plus review/ and a section at the end of CLAUDE.md
  if diff -r -x .git -x review -x CLAUDE.md "$work/bare" "$p" >"$work/diff" 2>&1; then
    ok "$v: outside review/ and CLAUDE.md the project is the bare one"
  else bad "$v: differs from bare outside review/ and CLAUDE.md: $(head -n 5 "$work/diff")"; fi
  n="$(wc -c < "$work/bare/CLAUDE.md")"
  if head -c "$n" "$p/CLAUDE.md" | cmp -s - "$work/bare/CLAUDE.md" && [ "$(wc -c < "$p/CLAUDE.md")" -gt "$n" ]; then
    ok "$v: CLAUDE.md is the bare one with a section after it"
  else bad "$v: CLAUDE.md is not the bare one with a section appended"; fi
  tail -c "+$((n + 1))" "$p/CLAUDE.md" >"$work/$v.section"
  [ "$(cat "$p/.git/sr-eval-variant")" = "$v" ] && ok "$v: .git/sr-eval-variant names it" || bad "$v: .git/sr-eval-variant is not $v"

  # 2. the rubrics, word for word
  case "$v" in
    review-batched) inv=invariants.md; mod=modules.md; mech=rules.md ;;
    *) inv=review.md; mod=review.md; mech=review.md ;;
  esac
  [ "$(ls "$p/review" | tr '\n' ' ')" = "$(printf '%s\n' "$inv" "$mod" "$mech" | sort -u | tr '\n' ' ')" ] &&
    ok "$v: review/ holds $(ls "$p/review" | tr '\n' ' ')" || bad "$v: review/ holds $(ls "$p/review" | tr '\n' ' ')"
  while read -r tpl find file; do
    expected "$rules/$tpl" "$here/$find" >"$work/want" || { bad "$v: $tpl has no template block"; continue; }
    grep -q -F -e '{%' -e '{{' "$work/want" && bad "$v: $tpl keeps template syntax outside its block"
    if holds "$p/review/$file" "$work/want"; then
      ok "$v: review/$file holds $tpl word for word ($(($(wc -l < "$work/want") - $(wc -l < "$here/$find"))) of the template's $(wc -l < "$rules/$tpl") lines, the rest is its template block)"
    else bad "$v: review/$file does not hold $tpl word for word: $(head -n 20 "$work/diff")"; fi
  done <<LIST
invariant-held/code-and-tests-hold.md.j2 invariants.find.md $inv
module-distinct/distinct-concern.md.j2 modules-distinct.find.md $mod
module-leaks/leak-or-use.md.j2 modules-leaks.find.md $mod
LIST
  grep -q -x -F '# Does the repository keep its six mechanical rules?' "$p/review/$mech" &&
    ok "$v: review/$mech states the mechanical rules" || bad "$v: review/$mech does not state the mechanical rules"
  grep -q -E '@[A-Z_]+@' "$p"/review/*.md "$work/$v.section" && bad "$v: a value was left unfilled (@NAME@)"

  # 3. nothing names the rules, a judge, a run or another preparation
  if grep -n -i -E 'sloprail|\beval|experiment|\bvariants?\b|\bbare\b' "$p"/review/*.md "$work/$v.section" >"$work/hits"; then
    bad "$v: names what it must not: $(head -n 5 "$work/hits")"
  else ok "$v: review/ and the CLAUDE.md section name no rules, run or other preparation"; fi
  if grep -n -i -E 'judge|\bscript' "$work/$v.section" >"$work/hits"; then
    bad "$v: the CLAUDE.md section names a judge or a script: $(cat "$work/hits")"
  else ok "$v: the CLAUDE.md section names no judge"; fi
done

if [ "$fails" -eq 0 ]; then echo "check: all passed"; else echo "check: $fails failed" >&2; exit 1; fi
