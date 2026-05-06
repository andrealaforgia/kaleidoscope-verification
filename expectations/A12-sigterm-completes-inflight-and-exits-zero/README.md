# A12 — sigterm-completes-inflight-and-exits-zero

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

Given aperture is running with no in-flight requests
When the operator sends `SIGTERM`
Then aperture's drain orchestrator emits
`event=shutdown_initiated signal=SIGTERM drain_deadline_ms=30000`
on stderr,
flips `/readyz` to 503 (`event=readiness_changed reason=shutdown_drain`),
emits `event=in_flight_drained drained_count=0`,
emits `event=shutdown_complete exit_code=0`,
and the process exits with code 0.

The deadline-exceeded branch (in-flight requests not completing
within `drain_deadline_ms`) is A14's domain.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A12**.
- External contract anchor: `docs/feature/aperture/slices/slice-08-graceful-shutdown.md` and `crates/aperture/src/shutdown.rs`.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:33 UTC
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: the runner confirms `/readyz=200`, sends `SIGTERM` via
  `docker compose kill -s SIGTERM aperture`, polls
  `docker inspect` until the container reaches state `exited`,
  reads its `ExitCode`, and asserts code 0 plus the drain
  lifecycle events on aperture's stderr.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — full lifecycle quoted.
- [`evidence/aperture.exit-code.txt`](evidence/aperture.exit-code.txt) — `0`.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — verbatim. Last six events:
  `event=readiness_changed ready=true reason=listeners_bound`,
  `event=ready`,
  `event=shutdown_initiated signal=SIGTERM drain_deadline_ms=30000`,
  `event=readiness_changed ready=false reason=shutdown_drain`,
  `event=in_flight_drained drained_count=0`,
  `event=shutdown_complete exit_code=0`.

## Issues

None.

## Notes

`drained_count=0` is honest: the runner did not load any in-flight
requests before SIGTERM. A future verification with a slow
downstream hold (see A14) will exercise non-zero drained_count.
