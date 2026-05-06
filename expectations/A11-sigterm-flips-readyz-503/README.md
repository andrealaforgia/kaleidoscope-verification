# A11 — sigterm-flips-readyz-503

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

Given aperture is running and `/readyz` returns 200
When the operator sends `SIGTERM` to the aperture process
Then the readiness state machine flips to `Draining` before the
drain orchestrator closes listeners
And `/readyz` returns 503 with body `draining\n` until the
listener closes.

The source-feed wording was "circa 100 ms"; the catalogue tightened
the contract to "before the drain completes" since no ADR pins a
hard millisecond bound. The observed transition latency is
captured in evidence and reported, not asserted as pass/fail.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A11**.
- External contract anchor:
  [`docs/feature/aperture/slices/slice-08-graceful-shutdown.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/feature/aperture/slices/slice-08-graceful-shutdown.md)
  and `crates/aperture/src/shutdown.rs:151` ("Flip readiness immediately
  so /readyz returns 503 \"draining\"").

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:32 UTC
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: dockerised harness; the runner confirms `/readyz=200`,
  sends `SIGTERM` via `docker compose kill -s SIGTERM aperture`,
  then polls `/readyz` for up to 5 s, capturing the response code
  and elapsed milliseconds since SIGTERM until 503 is observed.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner log.
  The transition was observed on the first poll after SIGTERM:
  `attempt 1 +0ms: code=503`, body `draining`.
- [`evidence/readyz.1.body.txt`](evidence/readyz.1.body.txt) — the response body byte-for-byte during the drain.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's stderr; the `event=readiness_changed reason=shutdown_drain ready=false` line preceded the listener close.

## Issues

None.

## Notes

The "0 ms" elapsed reading is the sub-second resolution of bash's
`SECONDS` arithmetic, not a perf claim. What it tells us is that
the flip happened before the runner could issue its first
post-SIGTERM curl, which validates the "before drain completes"
contract.
