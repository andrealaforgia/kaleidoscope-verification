# EG06 — log-trace-correlation-by-id

## Surface

`crates/kaleidoscope-gateway` → {Lumen, Ray} → log-query-api +
trace-query-api. The cross-pillar trace↔log join.

## Behaviour

A log carrying a `trace_id` and the matching trace can be correlated by id
across pillars: the log (via log-query-api) carries trace_id `T`, and the
trace (via trace-query-api `/by_id`) resolves to spans for that same `T`.
The same 16-byte id appears on both signals, so an operator can jump from
an error log to its trace. Covers UC-LOOP-005.

## Source

- External contract anchor: gateway preserves `trace_id` on logs (Lumen)
  and on spans (Ray); the two read APIs key on the same id.
- Use-case anchor: `kaleidoscope-usecases` UC-LOOP-005.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`d075748`).
- Method: ingest a trace; discover its `trace_id` T from trace-query-api;
  ingest a log stamped `--trace-id T`; log-query-api shows the log carries
  T (bytes→hex), and trace-query-api `/by_id T` returns the spans
  (2 spans). `log_trace_id == trace_id`.

## Evidence

- [`evidence/window.json`](evidence/window.json) — the trace id discovery.
- [`evidence/log.json`](evidence/log.json) — the log carrying T.
- [`evidence/byid.json`](evidence/byid.json) — the trace resolved by T.

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. telemetrygen can't pin a
shared trace id, so the runner discovers the real trace's id and stamps
the log with it — a faithful join, not a synthetic match. Complements
LQ10 (the log carries trace_id at all). UC-LOOP-006 (full-platform
restart) is the remaining heavier gap.
