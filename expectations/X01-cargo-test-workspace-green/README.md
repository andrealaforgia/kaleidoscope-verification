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
- Re-verified: 2026-06-07 UTC at HEAD (`1eda9d9`, after the
  perf-kpi-ci-non-gating-v0 DELIVER) — GREEN. That deliver supersedes the
  ADR-0058 gating: the wall-clock perf KPIs move to a non-gating CI job
  and the Gate-1 `KALEIDOSCOPE_PERF_TESTS=1` is deleted. It is pure
  CI-config (`.github/workflows/ci.yml`) plus un-ignoring two structural
  tests that assert the edited workflow shape — the perf test CODE is
  unchanged (still early-returns when `KALEIDOSCOPE_PERF_TESTS` is unset,
  which this runner deliberately leaves unset). So X01 is unaffected and
  now matches the non-gating intent. (Re-verified by RUNNING, per the N30
  lesson.)
- Last full verify: 2026-06-06 UTC at HEAD (`742536b`, after the
  spark-ingest-auth-v0 DELIVER) — GREEN, exit 0, every `test result: ok`
  including `place_onto_failing_disk_fails_loudly_and_is_not_durable`.
  **Now runs the tests as a NON-ROOT user (N30).** That cinder test
  (added `ddbe982`) chmods the WAL file read-only and asserts the append
  fails loudly; root bypasses the read-only bit, so under root the append
  succeeded and the test FAILED — a false RED in the harness, not a
  kaleidoscope defect (green in the implementer's non-root CI). Caught by
  re-running X01 after the spark DELIVER (I had not re-run it since
  `ddbe982` — the "test, don't assume" lesson). Fixed by `useradd tester`
  + `chown` the caches + `su tester -c cargo test`; the fault injection
  now bites and every workspace test runs faithfully. See known-gaps N30.
- Prior: 2026-06-01 at HEAD (`eed810d`) — GREEN, exit 0,
  every `test result: ok`. This is the first run after
  perf-kpi-ci-gating-v0 (ADR-0058) landed: the 28 wall-clock p95 KPI
  tests now early-return because the runner deliberately does NOT set
  `KALEIDOSCOPE_PERF_TESTS` (a Docker VM under variable host load cannot
  give a stable timing environment; CI enforces them instead). The
  workspace-test-green contract holds via the deterministic skip.
- Earlier `satisfied`: 2026-05-31 at `bbded968` (clean tree). The
  2026-05-19 `broken`
  verdict was a harness artefact, not a kaleidoscope defect: under
  Docker Desktop's ~2-4 GB VM cap a parallel `--all-targets` codegen
  run OOM-killed rustc and left partial rlibs, producing a spurious
  E0463 "can't find crate" cascade ([issue 004](../../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md),
  now `resolved`). Fixed by `CARGO_BUILD_JOBS=1` in the runner;
  cross-confirmed by Bea Implementer's clean 7.18s `self-observe`
  build and a local `-j1` full-workspace GREEN diagnostic.
- Previously satisfied: 2026-05-07 UTC at HEAD `c8d8a55`.
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

- [issue 004](../../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)
  — `cargo test --workspace --all-targets --locked` cannot
  resolve self-observe's path-dep workspace crates (aegis,
  cinder, lumen, pulse) on a fresh build.

## Notes

The `.no-compose` marker in this directory tells
`harness/run-expectation.sh` to skip the otelcol+aperture compose
stack since X01 only inspects the source tree via cargo. This was
introduced after a chained run of X01 + a compose-up-everything
expectation starved the Docker Desktop VM and caused the
subsequent expectation's `aperture` to miss its readiness gate.
