# L03 — loom-validate-exit-2-on-unreadable-dir

## Surface

Loom (operator change-control CLI). Operator-facing.

## Behaviour

`loom validate --rules <DIR>` exits 2 when DIR is unreadable (missing, permission denied). Distinct from exit 1 so CI can distinguish 'operator wrote a bad rule' from 'CI ran with a bad path'.

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
- [`evidence/L03.stdout.txt`](evidence/L03.stdout.txt) — combined stdout from the inline script (fixture + loom invocation).
- [`evidence/L03.stderr.txt`](evidence/L03.stderr.txt) — cargo build noise + loom's own stderr.

## Issues

None.

## Notes

`.no-compose` marker — Loom CLI has no runtime dependency on
the compose stack. Each runner is self-contained.
