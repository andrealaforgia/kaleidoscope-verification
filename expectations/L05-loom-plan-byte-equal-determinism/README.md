# L05 — loom-plan-byte-equal-determinism

## Surface

Loom (operator change-control CLI). Operator-facing.

## Behaviour

`loom plan --from <src> --to <dest>` produces byte-equal output across two consecutive invocations against the same input pair. KPI 2: the plan output is the source of truth for what an apply would change; non-determinism would make pre-merge review meaningless.

## Source

- External contract anchor:
  [`docs/feature/loom-v0/slices/slice-02-plan.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/feature/loom-v0/slices/slice-02-plan.md).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-12 UTC at HEAD (`149e4e43e346de38e964a33459e04f1b01a24465`).
- Method: `docker run rust:1.88-slim-bookworm` with the HEAD
  snapshot + persistent cargo caches; builds `loom` once
  (`cargo build --release -p loom --locked`), then runs the
  scenario via the shared helper `harness/run-loom.sh`. Inline
  fixtures (small TOML rule files) are created inside `/tmp/`
  in the container per run. The runner asserts on the loom
  binary's exit code and selected stdout markers.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/L05.stdout.txt`](evidence/L05.stdout.txt) — combined stdout from the inline script (fixture + loom invocation).
- [`evidence/L05.stderr.txt`](evidence/L05.stderr.txt) — cargo build noise + loom's own stderr.

## Issues

None.

## Notes

`.no-compose` marker — Loom CLI has no runtime dependency on
the compose stack. Each runner is self-contained.
