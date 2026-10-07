# sloprail-community

Everything built on [sloprail](https://github.com/sloprail/sloprail) that is not the core: demos, examples and plugins. Keeping them here keeps the core repo and its CI small. Each item here pins the sloprail version it was made with, so the two can evolve separately.

- `demos/<date>-<name>/`: a recorded demo run. `snapshots/<name>/` holds one or more archives of its agent trajectories.
- `examples/<name>/`: a shipped, working guardrail sample (its `.sloprail/`, README and eval fixtures). `examples/_shared`, `_onboarding` and the `_sloprail-*` directories hold shared eval scripts and the core plugins' eval fixtures.
- `tests/e2e/{harness,cli}/examples/0NN_<name>/`: the e2e tests of the examples, the same layout they had in sloprail.

The non-core plugins will move here later.

## Examples

`SLOPRAIL_VERSION` is the sloprail commit (or tag) the examples are tested against.

The example tests import sloprail's e2e harness (`github.com/sloprail/sloprail/tests/e2e/harness`), which builds the binaries, the plugin and the mock agent from a sloprail checkout, and one of them imports sloprail's `internal/` packages. Go forbids importing `internal/` across modules, so they do not build as a module of their own. They run inside a checkout of sloprail at the pinned version:

```
git clone https://github.com/sloprail/sloprail ../sloprail-checkout
git -C ../sloprail-checkout checkout "$(cat SLOPRAIL_VERSION)"
scripts/run-examples-shard.sh ../sloprail-checkout 1 6    # shard 1 of 6
```

`scripts/run-examples-shard.sh` copies `examples/` and `tests/e2e/*/examples/` into the checkout (replacing what it has there), runs `make mock` (the mock versions sloprail pins), and runs the shard with sloprail's own `scripts/e2e-shard.sh`, balanced by `scripts/e2e-shard-weights.txt`. The CI (`.github/workflows/examples.yml`) does the same for shards 1 to 6. The tests use the mock agent only, no model.

To move the examples to a newer sloprail, change `SLOPRAIL_VERSION` and let the CI run: that is the whole compatibility check.
