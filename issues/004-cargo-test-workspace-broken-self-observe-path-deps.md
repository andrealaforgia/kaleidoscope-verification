# 004 — `cargo test --workspace --all-targets --locked` broken: self-observe cannot resolve workspace path-dep crates

- Status: `resolved` — NOT a kaleidoscope defect; harness resource
  artefact. Fixed catalogue-side on 2026-05-31 by capping cargo's
  job count (`CARGO_BUILD_JOBS=1`) in the X01 and X05 runners.
- Expectations affected: X01 (now `satisfied`), X05 (now `satisfied`).

## Resolution (2026-05-31, HEAD bbded968)

This was misattributed to kaleidoscope. The E0463 "can't find crate
for `aegis`/`cinder`" cascade (and the broader variant that also hit
`augur`'s OWN test target failing to find the `augur` crate, plus
registry crates like `serde`/`tracing` that demonstrably compiled in
the same log) is the signature of a parallel-codegen OOM under Docker
Desktop's ~2-4 GB Linux-VM memory cap: rustc subprocesses get killed
mid-`--all-targets` and leave partial rlibs, so dependents fail to
load them.

Two independent observations closed it:
1. Bea Implementer (kaleidoscope side) ran `cargo build -p self-observe
   --all-targets --locked` at HEAD a29c431: Finished in 7.18s, exit 0.
   Her pre-commit `cargo test --workspace` is green on the compile.
   (message-bea-implementer-002, 2026-05-31.)
2. A `-j1` diagnostic in this harness ran the full
   `cargo test --workspace --all-targets --locked --jobs 1` to
   completion: CARGO_EXIT=0, every `test result: ok`.

Fix: `-e CARGO_BUILD_JOBS=1` in both runners' docker invocations.
After the fix, X01 and X05 both run green and exit 0 at bbded968
(see their evidence). A latent false-positive in the X01 assertion
(`grep 'FAILED'` matched a passing test NAMED
`failed_cinder_migrate_emits_no_otlp_line ... ok`) was fixed in the
same pass to anchor on cargo's real failure markers.

Lesson: a black-box harness failure is not automatically a defect in
the system under test. Attribution requires ruling out the harness
first. The previous filing of this issue skipped that step.

----------------------------------------------------------------
Original report (kept for the record; attribution was wrong)
----------------------------------------------------------------
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
