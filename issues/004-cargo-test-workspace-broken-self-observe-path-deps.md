# 004 — `cargo test --workspace --all-targets --locked` broken: self-observe cannot resolve workspace path-dep crates

- Status: `open`
- Expectations affected: X01 (broken), X05 (broken — pre-commit
  hook runs the same cargo test).
- Opened: 2026-05-19
- Kaleidoscope SHA at observation: `20777cb2f57b0a14db2608f88f8dae8b424e67d5`
- Confirmed reproducing at: `4855d69` (2026-05-19, re-verify-all
  pass, 5 commits after the original observation — all five are
  docs only, no code change, so the root cause is unchanged).

## Observed

A fresh `cargo test --workspace --all-targets --locked` against
the kaleidoscope HEAD snapshot fails to compile `self-observe`:

```
error[E0463]: can't find crate for `aegis`
  --> crates/self-observe/src/cinder_bridge.rs:51:5
   |
51 | use aegis::TenantId;
   |     ^^^^^ can't find crate

error[E0463]: can't find crate for `cinder`
  --> crates/self-observe/src/cinder_bridge.rs:52:5
   |
52 | use cinder::{MetricsRecorder as CinderRecorder, Tier};
   |     ^^^^^^ can't find crate
```

Plus 26 more errors of the same shape, and downstream test
targets (`crates/cinder/tests/v1_slice_01_wal_durability.rs` and
others) fail with the same pattern: workspace sibling crates
cannot find each other.

Compilation order in the log shows aegis, cinder, lumen, pulse,
sluice, aperture, loom all reach `Compiling …` before
self-observe starts. The deps are scheduled, then self-observe's
lib compile fails to resolve them.

Reproducible after fully wiping all three cargo caches
(`target/`, `cargo-registry/`, `cargo-git/`).

## Expected

Per the X01 contract:
`cargo test --workspace --all-targets --locked` exits 0 on a
fresh clone of the kaleidoscope HEAD. The pre-commit hook
(X05) runs the same command and is also expected to exit 0.

## Reproduction

```
cd ~/dev/kaleidoscope-expectations
git -C ~/dev/kaleidoscope rev-parse HEAD     # confirm 20777cb
rm -rf harness/.workspace-build-cache/{target,cargo-registry,cargo-git}
mkdir -p harness/.workspace-build-cache/{target,cargo-registry,cargo-git}
./harness/run-expectation.sh X01
# fails; cargo-test.stdout.txt shows E0463 on aegis/cinder/lumen/pulse
```

## Notes

`cargo build --workspace --release --locked` (X04's contract)
remains GREEN at the same SHA. The difference is `--release` +
no test targets vs debug profile + `--all-targets`. The
proc-macro / pin-project expansions visible later in the log
(tonic 0.12.3 with hundreds of `KindProj` / `InnerProj`
undeclared-type errors) hint that proc-macros are not being
expanded for test-mode compilation in this environment, but the
primary signal is the path-dep resolution failure on self-observe.

Hypotheses to explore:
- kaleidoscope CI may not have caught this if it uses a warmed
  build cache; a from-scratch CI run might reproduce.
- The workspace may have a feature-flag interaction that surfaces
  only under `--all-targets`.
- The container's rustc 1.88.0 may diverge subtly from CI's
  rustc; verify rustup channel.

This issue is the catalogue doing its job: a contract the
project relies on ("workspace cargo test green") fails on a
clean clone, and the catalogue surfaces it before it becomes
silently entrenched.
