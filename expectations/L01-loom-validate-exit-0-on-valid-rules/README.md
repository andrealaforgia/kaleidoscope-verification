# L01 — loom-validate-exit-0-on-valid-rules

## Surface

Loom (operator change-control CLI). Operator-facing.

## Behaviour

`loom validate --rules <DIR>` exits 0 when every TOML rule file under DIR loads cleanly through Beacon's loader. The contract underwrites pre-commit hooks: a green validate means the commit lets through.

## Source

- External contract anchor:
  [`docs/feature/loom-v0/slices/slice-01-validate.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/feature/loom-v0/slices/slice-01-validate.md).

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
- [`evidence/L01.stdout.txt`](evidence/L01.stdout.txt) — combined stdout from the inline script (fixture + loom invocation).
- [`evidence/L01.stderr.txt`](evidence/L01.stderr.txt) — cargo build noise + loom's own stderr.

## Issues

None.

## Notes

`.no-compose` marker — Loom CLI has no runtime dependency on
the compose stack. Each runner is self-contained.
