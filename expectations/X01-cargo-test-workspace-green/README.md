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
- Grounded GREEN: 2026-06-13 UTC at HEAD (`2552981`,
  `read-path-query-api-auth-v0` slice 2) — exit 0, 215 `test result: ok`
  lines, no `FAILED` / `error[` / lock error. The slice-1 `--locked` failure
  is RESOLVED. Mechanism (settled by black-box diff, correcting the original
  "missing edge" framing): the committed `Cargo.lock` is BYTE-IDENTICAL at
  `cdccb51` and `2552981`, and it already carried the `jsonwebtoken` /
  `reqwest` / `serde` edges for `log-query-api` and `trace-query-api`. At
  `cdccb51` those two manifests had not yet DECLARED those deps, so the lock
  was AHEAD of the manifests (over-specified relative to the declared graph)
  and `--locked` demanded regeneration → exit 101. Slice 2 added exactly
  those dev-deps to the `log-query-api` (+10) and `trace-query-api` (+11)
  `Cargo.toml`, reconciling the manifests with the already-present lock
  edges. Same command, same registry, reproduced side-by-side: `cdccb51`
  fails `--locked`, `2552981` passes (`cargo update --workspace --locked` →
  "Locking 0 packages", no error). Issue 015 RESOLVED. (Run non-root per
  N30; verified by RUNNING the full `--all-targets --locked` build, not just
  the lock-consistency gate.)
- Previously `broken`: 2026-06-08 UTC at HEAD (`cdccb51`,
  `read-path-query-api-auth-v0` slice 1) — exit 101. `cargo test --workspace
  --all-targets --locked` fails BEFORE compiling: `error: the lock file
  /src/Cargo.lock needs to be updated but --locked was passed to prevent
  this`. The commit added direct deps (`jsonwebtoken`, `reqwest`, `serde`,
  `tracing`) to `query-api` + `query-http-common` manifests but committed a
  `Cargo.lock` (+7 lines) that does not record the new dependency edges, so
  the committed tree is inconsistent under `--locked`. Reproduced with a
  CLEAN registry over the network (`cargo update --workspace --locked` →
  "Locking 0 packages" yet "lock file needs to be updated"), so it is NOT a
  harness cache artefact — it is the committed tree. Blast radius: every
  `--locked` build fails — CI, the `query-api`/`log-query-api`/`trace-query-api`
  Docker image builds (so Q/LQ/TQ expectations cannot rebuild at `cdccb51`),
  and the `cargo test --workspace --lib --locked` pre-commit hook. Classic
  committed-tree-vs-working-tree: the implementer's local tree has the
  updated lock (her hook/tests/mutation passed), the committed tree does not.
  See [issue 015](../../issues/015-cargo-lock-stale-at-cdccb51-locked-build-fails.md).
  Transition-proof: flips GREEN when a consistent `Cargo.lock` is committed.
- Previously `satisfied`: 2026-06-07 UTC at HEAD (`f919c59`, after the
  speed-up-local-precommit-v0 DELIVER `7e628d7`) — GREEN, exit 0. The deep
  `cargo test --workspace --all-targets --locked` (the run that moved OUT
  of the local hook and now gates only in CI) stays green here, and the
  new `crates/integration-suite/tests/v0_fast_precommit_structure.rs`
  (asserts the hook runs `--lib` and CI runs `--all-targets`) runs
  un-ignored under `--all-targets` and passes. X01 is the black-box guard
  that the deep run CI relies on still holds. (Run non-root per N30.)
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
