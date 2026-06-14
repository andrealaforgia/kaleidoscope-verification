# CRGEN01 — generator-send-to-see

## Surface

The first-party telemetry generator (`kaleidoscope-telemetrygen`,
experimentable-stack C3 / ADR-0077) driving the consolidated runtime —
our-generator → our-gateway (self-compatibility). Deliberately distinct from
PG1 (external SDK, cross-compatibility).

## Behaviour

Pointed at a live consolidated runtime (`OTEL_EXPORTER_OTLP_ENDPOINT` =
runtime :4317, `KALEIDOSCOPE_TENANT=acme`), the generator makes all three
signals queryable with no restart:

- metric `request_count` on :9090 `/api/v1/query_range` (≥1 series).
- app log `checkout failed: card declined` on :9091 `/api/v1/logs`
  (`body_contains=declined`).
- trace span `GET /api/v1/query_range`, service `kaleidoscope-demo`, under the
  fixed trace id `4bf92f3577b34da6a3ce929d0e0e4736` on :9092
  `/api/v1/traces/by_id` (deterministic by design).

## Source

- kaleidoscope generator deliver `4eacfb8` (slice 2), HEAD `3658376`.
  Env-driven; mandatory pre-flight reachability probe before emitting.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `3658376` (generator code
  `4eacfb8`; Cargo.lock consistent under `--locked`). Metric series 1, declined
  log hits 1, by-id spans 1 (service `kaleidoscope-demo`, span name
  `GET /api/v1/query_range`).
- Method: the runner builds the runtime and the generator images from the HEAD
  snapshot (catalogue `Dockerfile.kaleidoscope-runtime` +
  `Dockerfile.kaleidoscope-telemetrygen`), networks them, runs the generator
  against the runtime, and queries the three APIs.

## Notes

`.no-compose`: CRGEN01 manages its own runtime + generator containers. The
fixed trace id makes the by-id assertion deterministic. Companions: CRGEN02
(fail-closed reachability), CRGEN03 (tenant scoping), M1-LOOP (`make up` →
`make demo`). FIX-A (log noise) is the unfiltered-`:9091` counterpart and is now
gradeable since the generator is committed.
