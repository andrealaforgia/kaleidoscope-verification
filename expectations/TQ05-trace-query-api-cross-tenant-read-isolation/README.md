# TQ05 — trace-query-api-cross-tenant-read-isolation

## Surface

`crates/trace-query-api` binary (`/api/v1/traces` window arm over Ray),
driven end-to-end from `kaleidoscope-gateway` ingest. Operator-facing.

## Behaviour

Spans ingested through the gateway under `tenant-a` are NOT visible to a
`trace-query-api` instance bound to `tenant-b`
(`KALEIDOSCOPE_TRACE_QUERY_TENANT`), on the same durable Ray store.
tenant-b's window query for the service returns `[]` (200); the tenant-a
control returns the spans, so the empty result is isolation, not absence.

Covers **UC-TEN-003** (traces isolated by tenant). Also demonstrates
**UC-TEN-006** (per-instance tenant binding). The trace analogue of LQ07
(logs) and Q08 (metrics).

## Source

- External contract anchor: `trace-query-api` per-tenant Ray scoping
  (`KALEIDOSCOPE_TRACE_QUERY_TENANT`); gateway `KALEIDOSCOPE_DEFAULT_TENANT`.
- Use-case anchor: `kaleidoscope-usecases` UC-TEN-003 (and UC-TEN-006).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: gateway ingest 5 traces for `tq05-pilot` under tenant-a, flush;
  trace-query-api/tenant-b window → 200 + 0 spans; tenant-a → 200 + ≥1.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/tq05-tenant-b.json`](evidence/tq05-tenant-b.json) (empty), [`evidence/tq05-tenant-a.json`](evidence/tq05-tenant-a.json) (control).

## Issues

None.

## Notes

`.no-compose` marker; built via `harness/run-eg.sh`. Isolation, not
absence: the tenant-a control proves the spans are present and durable.
