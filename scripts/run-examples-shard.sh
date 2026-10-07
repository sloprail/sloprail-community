#!/usr/bin/env bash
# Runs shard INDEX of COUNT of the example e2e inside a sloprail checkout.
#
#   scripts/run-examples-shard.sh <sloprail-checkout> <index> <count>
#
# The example tests import github.com/sloprail/sloprail/tests/e2e/harness (and
# some, sloprail's internal/ packages), so they cannot build as a module of their
# own: they run inside a checkout of sloprail at the version in SLOPRAIL_VERSION,
# with sloprail's own harness, mock pins and shard script. This copies the
# examples and their tests over whatever the checkout has at those paths, so the
# community copy is what runs, then runs the shard.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
sr="$(cd "${1:?usage: run-examples-shard.sh CHECKOUT INDEX COUNT}" && pwd)"
index="${2:?usage: run-examples-shard.sh CHECKOUT INDEX COUNT}"
count="${3:?usage: run-examples-shard.sh CHECKOUT INDEX COUNT}"

rm -rf "$sr/examples" "$sr/tests/e2e/harness/examples" "$sr/tests/e2e/cli/examples"
cp -R "$here/examples" "$sr/examples"
mkdir -p "$sr/tests/e2e/harness" "$sr/tests/e2e/cli"
cp -R "$here/tests/e2e/harness/examples" "$sr/tests/e2e/harness/examples"
cp -R "$here/tests/e2e/cli/examples" "$sr/tests/e2e/cli/examples"
# Measured seconds for balancing the shards; the checkout's own file may lack them.
cat "$here/scripts/e2e-shard-weights.txt" >> "$sr/scripts/e2e-shard-weights.txt"

cd "$sr"
make mock
test -x .bin/a10n-claude-mock || { echo "a10n-claude-mock is not in .bin/: every e2e package would SKIP and report ok" >&2; exit 1; }
scripts/e2e-shard.sh "$index" "$count" run ./tests/e2e/harness/examples/... ./tests/e2e/cli/examples/...
