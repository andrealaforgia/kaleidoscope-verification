# A10 — readyz-200-when-healthy

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

Given aperture has started and bound both listeners (gRPC `:4317` and
HTTP `:4318`)
When a client issues `GET http://<host>:4318/readyz`
Then aperture responds HTTP `200` with body `ready\n`.

Before listeners bind, `/readyz` returns 503 with body `starting\n`. The
flip from `starting` to `ready` is signalled by an
`event=readiness_changed` line on aperture's stderr with
`reason=listeners_bound`.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A10**.
- External contract anchor:
  [`docs/feature/aperture/slices/slice-02-http-protobuf-and-readiness.md`](https://github.com/andrealaforgia/kaleidoscope/blob/3d3c99f061a3c76d48ac9d2a824612d8bdc37b68/docs/feature/aperture/slices/slice-02-http-protobuf-and-readiness.md)
  line 9 ("`/readyz` (200 once both listeners are bound, 503 during
  startup)") and line 43 ("`GET /readyz` returns 503 `\"starting\"`
  before listeners bind, 200 `\"ready\"` after").

## Verification

- Status: `satisfied`
- Last verified: 2026-05-27 UTC at HEAD (`b71ad8a`). Code=200,
  body "ready\n" at attempt 1. Cycle 4's failure was confirmed
  flake (cycle 5 re-verifies A01-A04 + A11 all GREEN and A10
  itself green at first retry). Issue 006 closed.
- Previous satisfaction history: 2026-05-27 at `74920c7` and
  earlier across multiple cycles.
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: dockerised harness; aperture built from the HEAD snapshot;
  `runner.sh` polls `http://localhost:4318/readyz` until HTTP 200,
  capturing the response code and body verbatim.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) —
  pinning record (SHA, dirty flag, host, timestamp).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner
  log: one attempt, code 200.
- [`evidence/readyz.code.txt`](evidence/readyz.code.txt) — the literal
  HTTP status code observed (`200`).
- [`evidence/readyz.body.txt`](evidence/readyz.body.txt) — the
  response body byte-for-byte (`ready\n`, six bytes).
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) —
  aperture's structured stderr. The lines `event=listener_bound`
  (`transport=grpc`, `transport=http`) precede
  `event=readiness_changed reason=listeners_bound ready=true`,
  matching the slice-02 contract.

## Issues

None.

## Notes

The captured file `evidence/otlp-received.jsonl` is empty as expected:
this expectation issues no OTLP traffic.
