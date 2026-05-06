# X04 — cargo-build-release-produces-binary

## Surface

Operations / build. Build-engineer-facing.

## Behaviour

`cargo build --workspace --release --locked` against the
kaleidoscope tree at `HEAD` succeeds and produces an executable
`target/release/aperture` binary. The build runs in a
`rust:1.88-slim-bookworm` container so the toolchain is the one
the project pins (rustc 1.88, edition 2021).

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X4**.
- External contract anchor:
  [`Cargo.toml`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/Cargo.toml)
  workspace declaration plus
  [`rust-toolchain.toml`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/rust-toolchain.toml)
  pinning channel = "1.88".

## Verification

- Status: `satisfied`
- Last verified: 2026-05-07T00:43Z
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: `docker run rust:1.88-slim-bookworm` mounting the
  HEAD snapshot under `/src` plus persistent host-side caches for
  `/usr/local/cargo/{registry,git}` and `/src/target`. Inside the
  container: `apt-get install pkg-config libssl-dev`, then
  `cargo build --workspace --release --locked`. The runner asserts
  that `target/release/aperture` exists, is executable, and reports
  its `stat` output.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/cargo-build.stdout.txt`](evidence/cargo-build.stdout.txt) — full build log. Last lines:
  - `rustc 1.88.0 (6b00bc388 2025-06-23)`
  - `cargo 1.88.0 (873a06493 2025-05-10)`
  - `Finished release profile [optimized] target(s) in 30.42s`
  - `size=8192008 mode=-rwxr-xr-x path=target/release/aperture`
- [`evidence/cargo-build.stderr.txt`](evidence/cargo-build.stderr.txt) — cargo's per-crate compile lines (one per crate in the dependency closure plus the four workspace members `aperture`, `otlp-conformance-harness`, `spark`, `sieve`).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner log.

## Issues

None.

## Notes

The build host is macOS / arm64; the container runs aarch64 Linux.
The aperture binary produced is therefore Linux/aarch64, not macOS/arm64.
That is the right thing for verification (kaleidoscope's deploy
target is Linux). For developer-loop ergonomics, `cargo build` on
the host produces the macOS/arm64 binary; we do not exercise that
in EDD.

The cache mounts under `harness/.workspace-build-cache/` survive
between runs so subsequent X04 verifications complete in seconds
rather than the ~60-90 s cold build.
