# TQ03 — traces-window-arm-parse-guards

## Surface

trace-query-api (Ray traces read HTTP service), window arm
`GET /api/v1/traces`. Operator/integrator-facing.

## Behaviour

Given trace-query-api is running with a resolved tenant and an empty Ray
store
When the window arm is queried
Then it guards its inputs BEFORE the store, and the store is never
touched on a refusal path:

- a missing `service` is the traces-only required-parameter `400` with
  the literal reason `invalid request: service is required` (logs do not
  require a service; this is the one structural divergence, ADR-0048);
- a window of `86401` seconds (one over the cap) is the shared
  window-cap `400` whose reason names `window exceeds 86400 seconds`
  (ADR-0050 Decision 1);
- a well-formed request (`service` present, valid window) is accepted
  with `200` (empty array on the empty store), proving the two `400`s
  are the parse guards, not a blanket rejection.

## Source

- trace-query-api window arm contract (ADR-0048 service-required,
  ADR-0050 window cap), shared via query-http-common (ADR-0054).
- External contract anchors: `read_required_service`
  (`"invalid request: service is required"`) and the window-cap check
  (`REASON_WINDOW_TOO_LARGE = "window exceeds 86400 seconds"`) at
  [`crates/trace-query-api/src/lib.rs:139`](https://github.com/andrealaforgia/kaleidoscope/blob/acca3ec95293c0d757600b2df58549da68c2b5c1/crates/trace-query-api/src/lib.rs#L139).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`acca3ec`). GREEN at first
  attempt: `code_a_noservice=400` (`invalid request: service is
  required`), `code_b_bigwindow=400` (`window exceeds 86400 seconds`),
  `code_c_valid=200`.
- Method: dockerised harness via `harness/run-trace-query-api.sh`
  (catalogue-authored `harness/Dockerfile.trace-query-api`). A
  three-shot scenario against a fresh empty `/data` (Ray pillar root)
  with `KALEIDOSCOPE_TRACE_QUERY_TENANT=acme`, host port `19098`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `acca3ec`). dirty `yes`: the dirty set includes the three
  read binaries' `main.rs` (the implementer's UNCOMMITTED
  read-api-tracing-subscriber-v0 edit); the build used `git archive
  HEAD` so it is not in the binary, and TQ03 asserts on HTTP responses,
  not logs.
- [`evidence/tq03-a-noservice.json`](evidence/tq03-a-noservice.json),
  [`evidence/tq03-b-bigwindow.json`](evidence/tq03-b-bigwindow.json),
  [`evidence/tq03-c-valid.json`](evidence/tq03-c-valid.json) — the three
  responses.

## Issues

None.

## Notes

Third TQ expectation. Complements TQ02 (window-arm happy-path
round-trip) by pinning the window arm's two parse guards and the
traces-only required-`service` divergence. Unique high host port
(`19098`) per N27.
