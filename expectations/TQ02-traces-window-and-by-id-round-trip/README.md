# TQ02 — traces-window-and-by-id-round-trip

## Surface

kaleidoscope-gateway (OTLP receiver, Ray sink) + trace-query-api
(`/api/v1/traces` and `/api/v1/traces/by_id` over Ray). End-to-end,
operator/integrator-facing.

## Behaviour

Given spans of a known service are ingested through the gateway into the
durable Ray store and read back through trace-query-api over the same
store and tenant
When the two read arms are exercised
Then both return the ingested data:

- the window arm `GET /api/v1/traces?service=tq02-pilot&start=&end=`
  returns `200` with the ingested spans, every one carrying
  `resource_attributes."service.name" == tq02-pilot`; a bogus service
  returns `200` with the empty array `[]` (the service filter filters);
- a `trace_id` discovered from the window response, fed to the by-id arm
  `GET /api/v1/traces/by_id?trace_id=<32-hex>`, returns `200` with every
  span sharing that `trace_id`.

This proves both read arms return ingested data across the real durable
boundary. TQ01 proved only the by-id parser (malformed → 400); TQ02
closes the round-trip on both arms with one fixture.

## Source

- trace-query-api window arm (ADR-0048) + by-id arm
  (trace-lookup-by-id-v0, feat `3908240`, ADR-0053); gateway Ray sink at
  [`crates/kaleidoscope-gateway/src/main.rs:71`](https://github.com/andrealaforgia/kaleidoscope/blob/acca3ec95293c0d757600b2df58549da68c2b5c1/crates/kaleidoscope-gateway/src/main.rs#L71).
- External contract anchors: `handle_traces` and `handle_traces_by_id`
  at
  [`crates/trace-query-api/src/lib.rs:126`](https://github.com/andrealaforgia/kaleidoscope/blob/acca3ec95293c0d757600b2df58549da68c2b5c1/crates/trace-query-api/src/lib.rs#L126);
  `TraceId` serialises as 32-hex (`hex::encode`) at
  [`crates/ray/src/span.rs:67`](https://github.com/andrealaforgia/kaleidoscope/blob/acca3ec95293c0d757600b2df58549da68c2b5c1/crates/ray/src/span.rs#L67),
  which is why a window-response `trace_id` feeds the by-id arm directly.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`acca3ec`). GREEN at first
  attempt: window arm returned 10 spans (5 traces × root+child) all
  carrying `service=tq02-pilot`; bogus service returned `[]`; the
  discovered `trace_id ece636b61a81ad53d94be410cb15f29a` resolved via
  by-id to 2 spans, all sharing it.
- Method: dockerised harness via `harness/run-eg.sh` (gateway +
  trace-query-api built from the HEAD snapshot; trace-query-api via the
  catalogue-authored `harness/Dockerfile.trace-query-api`). Gateway on
  host port `14322`; `telemetrygen:v0.114.0 traces --traces 5
  --service tq02-pilot`; SIGTERM to flush Ray; then trace-query-api on
  the SAME `/data` (host port `19096`) queried on both arms.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `acca3ec`). **dirty `yes`, and the dirty set DOES include
  `crates/trace-query-api/src/main.rs`** — but that is the implementer's
  in-flight `read-api-tracing-subscriber-v0` edit (adding the subscriber)
  sitting UNCOMMITTED in the working tree; the build used
  `git archive HEAD`, so it is NOT in the binary under test, and the
  committed `main.rs` at `acca3ec` is unchanged. TQ02 asserts on HTTP
  responses, not on container logs, so the subscriber is orthogonal
  regardless. See `evidence/kaleidoscope-dirty.status`.
- [`evidence/tq02-window.json`](evidence/tq02-window.json) — the window
  arm's 10-span response.
- [`evidence/tq02-window-absent.json`](evidence/tq02-window-absent.json)
  — the bogus-service empty array.
- [`evidence/tq02-byid.json`](evidence/tq02-byid.json) — the by-id
  response for the discovered trace_id.
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt),
  [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/trace-query-api.stderr.txt`](evidence/trace-query-api.stderr.txt).

## Issues

None. (trace-query-api shares the issue-005 missing-subscriber gap, which
the implementer is actively fixing — see the dirty main.rs note above —
but TQ02 is independent of it.)

## Notes

Second TQ expectation; closes the trace read round-trip on both arms.
`harness/run-eg.sh` extended to build trace-query-api too. Unique high
host ports (`14322`, `19096`) per N27. The dirty `main.rs` is an early
signal that read-api-tracing-subscriber-v0 DELIVER is near; when it
lands committed, TQ01/LQ01/Q01 get re-verified and tightened onto the
structured `health.startup.refused` event.
