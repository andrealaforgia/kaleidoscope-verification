# EG05 — three-pillars-one-stream

## Surface

`crates/kaleidoscope-gateway` → {Pulse, Lumen, Ray} → query-api +
log-query-api + trace-query-api. Operator-facing integration thesis.

## Behaviour

A single gateway ingesting one OTLP stream that carries all three signals
(metrics + logs + traces) stores each into its own pillar, and each pillar
is INDEPENDENTLY queryable via its own read API from the same populated
data volume — no cross-pillar interference:
- metric `gen` via query-api → ≥1 series;
- log (body marker) via log-query-api → ≥1 record;
- trace (by service) via trace-query-api → ≥1 span.

Covers UC-LOOP-004 (three pillars from one stream).

## Source

- External contract anchor: gateway multi-signal demux into the three
  pillars; the three read APIs over one volume.
- Use-case anchor: `kaleidoscope-usecases` UC-LOOP-004.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`027b63a`).
- Method: one gateway (default=acme) ingests metrics, logs and traces in
  turn; query-api (metric=1 series), log-query-api (log=4), trace-query-api
  (trace=6 spans) each return their own signal.

## Evidence

- [`evidence/metric.json`](evidence/metric.json), [`evidence/log.json`](evidence/log.json), [`evidence/trace.json`](evidence/trace.json).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh` (gateway + all three read
APIs). Composes EG01 (metric), LQ02 (log), TQ02 (trace) into one
populated volume. UC-LOOP-005 (log↔trace correlation) is partially shown
by LQ10; UC-LOOP-006 (full-platform restart) is the remaining heavier gap.
