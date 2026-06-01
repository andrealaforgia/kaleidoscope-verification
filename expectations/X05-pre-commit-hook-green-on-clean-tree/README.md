# X05 — pre-commit-hook-green-on-clean-tree

## Surface

Operations / build. Build-engineer-facing.

## Behaviour

`scripts/hooks/pre-commit` runs all four local quality gates (cargo
fmt --check, cargo clippy --all-targets --locked -- -D warnings,
cargo deny --all-features check, cargo test --workspace
--all-targets --locked) and exits 0 with the success marker
`[pass] all pre-commit gates green`. This is the kaleidoscope
contributor's local quality gate, mirroring as much of the CI
contract (ADR-0005) as can run in seconds.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X5**.
- External contract anchor:
  [`scripts/hooks/pre-commit`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/scripts/hooks/pre-commit)
  itself.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`2e8bc8b`, clean tree) — GREEN,
  exit 0, `[pass] all pre-commit gates green`. First run after
  perf-kpi-ci-gating-v0 (ADR-0058): the hook does not set
  `KALEIDOSCOPE_PERF_TESTS` (nor does this runner), so the 28 p95 KPI
  tests skip deterministically, matching the hook's own local posture.
- Earlier `satisfied`: 2026-05-31 at `bbded968`. The 2026-05-19 `broken`
  verdict inherited X01's harness OOM artefact, not a kaleidoscope
  defect; see
  [issue 004](../../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)
  (now `resolved`). Fixed by `CARGO_BUILD_JOBS=1` in the runner.
- Previously satisfied: 2026-05-07 UTC at HEAD `c8d8a55`.
- Method: identical setup pattern to X02 (cargo-deny installed
  into `harness/.workspace-build-cache/cargo-install/` cache),
  then `docker run rust:1.88-slim-bookworm` against the snapshot
  read-write (the hook needs target/ writable). Inside the
  container: `apt-get install pkg-config libssl-dev ca-certificates
  git`, `rustup component add rustfmt clippy`, then `bash
  scripts/hooks/pre-commit`. The runner asserts the hook exits 0
  AND the literal success marker `[pass] all pre-commit gates
  green` appears.
- Workaround: `CARGO_PROFILE_TEST_DEBUG=0` for the cargo test
  step, same reason as X01.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/pre-commit.stdout.txt`](evidence/pre-commit.stdout.txt) — the hook's full output. Last line: `[pass] all pre-commit gates green`. Intermediate sections show fmt-check ok, clippy ok with -D warnings, cargo-deny ok, cargo test ok per workspace member.

## Issues

- [issue 004](../../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)
  — the workspace cargo test step inside the hook reproduces
  X01's failure mode (self-observe path-dep resolution).

## Notes

X05 is a superset of X01 + X02 plus fmt and clippy. Each
expectation has its own evidence file capture; satisfying X05
does not satisfy X01 or X02 by transitivity in catalogue
bookkeeping (each contract is verified independently). In
practice they tend to move together.
