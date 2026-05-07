# X01 — cargo-test-workspace-green

## Surface

Operations / build. Build-engineer-facing.

## Behaviour

`cargo test --workspace --all-targets --locked` against the
kaleidoscope HEAD snapshot exits green. Every workspace member
(`aperture`, `otlp-conformance-harness`, `spark`, `sieve`) runs its
test suites and every one reports `test result: ... ok`. This is
Gate 1 of the CI contract per ADR-0005.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X1**.
- External contract anchor:
  [`docs/product/architecture/adr-0005-ci-contract.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0005-ci-contract.md) (Gate 1).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-07 UTC at HEAD.
- Method: `docker run rust:1.88-slim-bookworm` mounting the snapshot
  read-write under `/src` plus persistent caches under
  `harness/.workspace-build-cache/`. Inside the container:
  `apt-get install pkg-config libssl-dev`, then `cargo test
  --workspace --all-targets --locked`. The runner asserts every
  `test result:` line ends in `ok` and that the output contains no
  `FAILED` / `test failed` markers.
- Workaround: `CARGO_PROFILE_TEST_DEBUG=0` is set inside the
  container because Docker Desktop's default macOS memory cap
  OOM-kills `ld` linking the slice_05 test binary at full
  debuginfo. Suppressing test-binary debug symbols keeps memory
  bounded; the contract being verified is "tests run green",
  which debuginfo presence is orthogonal to.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/cargo-test.stdout.txt`](evidence/cargo-test.stdout.txt) — full cargo test log; per-binary `test result:` lines and final compilation summary.
- [`evidence/cargo-test.stderr.txt`](evidence/cargo-test.stderr.txt) — apt-get + rustup info noise.

## Issues

None.

## Notes

The `.no-compose` marker in this directory tells
`harness/run-expectation.sh` to skip the otelcol+aperture compose
stack since X01 only inspects the source tree via cargo. This was
introduced after a chained run of X01 + a compose-up-everything
expectation starved the Docker Desktop VM and caused the
subsequent expectation's `aperture` to miss its readiness gate.
