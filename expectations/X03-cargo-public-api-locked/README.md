# X03 — cargo-public-api-locked

## Surface

Operations / supply chain. Build-engineer-facing.

## Behaviour

`cargo public-api -p otlp-conformance-harness` and
`cargo public-api -p spark` (run under the project-pinned nightly
`nightly-2026-04-15`) produce non-empty, parseable surface
listings for both crates. Each listing contains real Rust public
items (`pub mod`, `pub fn`, `pub enum`, `pub struct`, `impl`).

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X3**.
- External contract anchors:
  [`docs/product/architecture/adr-0001-public-api-surface-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0001-public-api-surface-and-crate-layout.md)
  and
  [`docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md).
  Nightly pin source:
  [`.github/workflows/ci.yml`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/.github/workflows/ci.yml)
  `NIGHTLY_PIN: nightly-2026-04-15`.

## Verification

- Status: `satisfied` (with caveat — see Notes)
- Last verified: 2026-05-07 UTC at HEAD.
- Method: `docker run rust:1.88-slim-bookworm` with a host-mounted
  `RUSTUP_HOME=/var/rustup-home` so the pinned nightly toolchain
  installation persists across cache filesystems. First run seeds
  `/var/rustup-home` from the image's stock `/usr/local/rustup`,
  then installs `nightly-2026-04-15` via rustup, then `cargo
  install --locked cargo-public-api` (cached). Per-crate run:
  `RUSTUP_TOOLCHAIN=nightly-2026-04-15 cargo public-api -p
  <crate> --simplified` with stdout (the surface) captured to
  `public-api.<crate>.txt` and stderr (compile noise) captured
  separately.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/setup.txt`](evidence/setup.txt) — nightly toolchain + cargo-public-api install log; final lines confirm `cargo-public-api 0.51.0` and `nightly-2026-04-15-aarch64-unknown-linux-gnu`.
- [`evidence/public-api.otlp-conformance-harness.txt`](evidence/public-api.otlp-conformance-harness.txt) — 127 surface lines. Top items include `pub mod otlp_conformance_harness`, `pub enum ByteOffset` with its variants, plus the canonical `Clone`/`Display`/`Debug` impls.
- [`evidence/public-api.spark.txt`](evidence/public-api.spark.txt) — 57 surface lines. Top items include `pub mod spark`, `pub enum SparkError` with its variants (`ExporterInitFailed`, `GlobalAlreadyInitialised`, etc.).

## Issues

None directly.

## Notes

The kaleidoscope CI Gate 2 form is
`cargo public-api --diff-git-checkouts main HEAD`, which compares
the surface at HEAD against the surface at `origin/main` to gate
deliberate-vs-accidental API breaks. Our snapshot does not carry a
remote `main` reference, so this runner exercises the weaker
"tool runs green and emits a surface" contract, not the
diff-vs-baseline contract. A stronger follow-on would either:
(a) clone main into the snapshot before running, or (b) commit a
frozen `public-api.txt` snapshot in this repo and diff against it
on each run. Either is a follow-up.
