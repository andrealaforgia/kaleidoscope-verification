# A13 — sigint-same-drain-orchestration

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

`SIGINT` triggers the same drain orchestration as `SIGTERM` (A12):
shutdown_initiated → readiness_changed (drain) → in_flight_drained →
shutdown_complete, exit code 0.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A13**.
- External contract anchor: `docs/feature/aperture/slices/slice-08-graceful-shutdown.md` and `crates/aperture/src/shutdown.rs`.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:33 UTC
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: identical to A12 except the signal is `SIGINT`. Same
  poll-for-exited then read ExitCode pattern.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/aperture.exit-code.txt`](evidence/aperture.exit-code.txt) — `0`.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — same shape as A12 but
  `event=shutdown_initiated signal=SIGINT drain_deadline_ms=30000`.

## Issues

None.

## Notes

Same caveat as A12 about `drained_count=0`. The orchestration is
signal-agnostic; only the recorded `signal` field differs.
