#!/usr/bin/env bash
# Runs the smoke evals (examples/_smoke/eval/*) for each real harness, every
# (harness, case) pair in parallel, and prints a harness x case table.
#
#   scripts/run-smoke-evals.sh [--harness claude,codex,cursor] [--case a,b]
#                              [--jobs N] [--sloprail DIR] [--model M]
#
# These are REAL agent runs (a cheap model, about a minute each). They need:
#   - a sloprail checkout with its binaries built (`make build` there): sr-eval
#     builds that checkout fresh for every run and installs its plugin for the
#     agent, so the code under test is the checkout's. --sloprail DIR, else
#     $SLOPRAIL_CHECKOUT, else ../sloprail beside this repo.
#   - each harness's CLI installed and logged in (claude, codex, cursor-agent).
# Each run gets a HOME of its own inside a temp workspace (sr-eval's rule): your
# real ~/.claude, ~/.codex and ~/.cursor are never written. Nothing is archived.
#
# Exit status: 0 when every cell is as expected, 1 otherwise.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
all_harnesses="claude codex cursor"
harnesses="$all_harnesses"
cases=""
jobs=0
sloprail="${SLOPRAIL_CHECKOUT:-}"
model=""

while [ $# -gt 0 ]; do
  case "$1" in
    --harness) harnesses="${2//,/ }"; shift 2 ;;
    --case) cases="${2//,/ }"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --sloprail) sloprail="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    -h | --help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- Expected failures, in plain view -------------------------------------
# A (harness:case) listed here is EXPECTED TO FAIL. The table shows it as XFAIL
# (it failed, as expected) or XPASS (it passed: the expectation is stale, which
# fails the run so it gets deleted). It is not skipped: it runs every time.
EXPECT_FAIL=(
  "cursor:stop-gate"
  "cursor:file-guard-stop"
)
EXPECT_FAIL_WHY="Cursor's stop hook never fires under 'cursor-agent -p', which is how sr-eval runs Cursor today. Remove these two lines when sr-eval's Cursor TUI mode lands (branch feat/sr-eval-cursor-tui)."
# ----------------------------------------------------------------------------

if [ -z "$sloprail" ]; then
  sloprail="$(cd "$here/../sloprail" 2>/dev/null && pwd)" || sloprail=""
fi
if [ -z "$sloprail" ] || [ ! -x "$sloprail/bin/sr-eval" ]; then
  echo "no built sloprail checkout: pass --sloprail DIR (or set SLOPRAIL_CHECKOUT) to a checkout where 'make build' has run (needs DIR/bin/sr-eval)" >&2
  exit 2
fi
sloprail="$(cd "$sloprail" && pwd)"

evals="$here/examples/_smoke/eval"
if [ -z "$cases" ]; then
  for d in "$evals"/*/; do
    [ -f "$d/fixture.yaml" ] && cases="$cases $(basename "$d")"
  done
fi
for c in $cases; do
  [ -f "$evals/$c/fixture.yaml" ] || { echo "no such case: $c (have: $(ls "$evals" | tr '\n' ' '))" >&2; exit 2; }
done
for h in $harnesses; do
  case " $all_harnesses " in *" $h "*) ;; *) echo "unknown harness: $h (one of: $all_harnesses)" >&2; exit 2 ;; esac
done

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

run_one() { # harness case
  local h="$1" c="$2" start end code
  start="$(date +%s)"
  (cd "$sloprail" && ./bin/sr-eval run --fixture "$evals/$c" --harness "$h" --no-archive ${model:+--model "$model"}) > "$out/$h.$c.log" 2>&1
  code=$?
  end="$(date +%s)"
  printf '%s %s\n' "$code" "$((end - start))" > "$out/$h.$c.res"
}

total=0
for h in $harnesses; do for c in $cases; do total=$((total + 1)); done; done
echo "running $total smoke eval(s) ($harnesses x $cases), $([ "$jobs" -gt 0 ] && echo "$jobs at a time" || echo "all in parallel")..." >&2

for h in $harnesses; do
  for c in $cases; do
    if [ "$jobs" -gt 0 ]; then
      while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$jobs" ]; do sleep 1; done
    fi
    run_one "$h" "$c" &
  done
done
wait

expected_fail() { # harness case
  local e
  for e in "${EXPECT_FAIL[@]}"; do [ "$e" = "$1:$2" ] && return 0; done
  return 1
}

# cell: the verdict of one run, "<VERDICT> <seconds>s".
status=0
notes=""
for h in $harnesses; do
  for c in $cases; do
    read -r code secs < "$out/$h.$c.res"
    case "$code" in
      0) v=PASS ;;
      1) v=FAIL ;;
      *) v=ERROR ;;
    esac
    if expected_fail "$h" "$c"; then
      case "$v" in
        PASS) v=XPASS; status=1; notes="$notes\n  $h/$c passed though listed in EXPECT_FAIL: remove the expectation." ;;
        *) v=XFAIL ;;
      esac
    elif [ "$v" != PASS ]; then
      status=1
      reason="$(grep -E '^sr-eval: (FAIL|ERROR)' "$out/$h.$c.log" | tail -1 | cut -c1-300)"
      notes="$notes\n  $h/$c $v: ${reason:-see the log}"
    fi
    printf '%s' "$v ${secs}s" > "$out/$h.$c.cell"
  done
done

w=26
printf '\n%-*s' "$w" "case"
for h in $harnesses; do printf '%-16s' "$h"; done
printf '\n'
for c in $cases; do
  printf '%-*s' "$w" "$c"
  for h in $harnesses; do printf '%-16s' "$(cat "$out/$h.$c.cell")"; done
  printf '\n'
done
printf '\nPASS ok | FAIL the scorer said no | ERROR the run could not be completed | XFAIL failed as expected | XPASS passed but was expected to fail\n'
for e in "${EXPECT_FAIL[@]}"; do
  h="${e%%:*}"
  case " $harnesses " in *" $h "*) printf 'expected to fail: %s\n  %s\n' "$e" "$EXPECT_FAIL_WHY"; break ;; esac
done
if [ -n "$notes" ]; then
  printf '\nunexpected:%b\n' "$notes"
  if [ -n "${SMOKE_LOGS:-}" ]; then
    mkdir -p "$SMOKE_LOGS" && cp "$out"/*.log "$SMOKE_LOGS"/ && printf 'logs copied to %s\n' "$SMOKE_LOGS"
  else
    printf 'set SMOKE_LOGS=<dir> to keep the per-run logs\n'
  fi
fi
exit "$status"
