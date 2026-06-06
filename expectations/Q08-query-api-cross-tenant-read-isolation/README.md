# Q08 — query-api-cross-tenant-read-isolation

## Surface

`crates/query-api` binary (`/api/v1/query_range` over Pulse), driven
end-to-end from `kaleidoscope-gateway` ingest. Operator-facing.

## Behaviour

A metric ingested through the gateway under `tenant-a` is NOT visible to
a `query-api` instance bound to `tenant-b` (`KALEIDOSCOPE_QUERY_TENANT`),
even on the same durable Pulse store. tenant-b's `query_range` returns
`status=success` with an empty matrix; the tenant-a control returns the
series, so the empty result is isolation, not absence.

Covers **UC-TEN-002** (metrics isolated by tenant). Also demonstrates
**UC-TEN-006** (per-instance tenant binding: the tenant is fixed by the
env var, there is no query param to widen scope to foreign data). The
query-api metric analogue of LQ07 (logs) and TQ05 (traces).

## Source

- External contract anchor: `query-api` per-tenant Pulse scoping
  (`KALEIDOSCOPE_QUERY_TENANT`); gateway `KALEIDOSCOPE_DEFAULT_TENANT`.
- Use-case anchor: `kaleidoscope-usecases` UC-TEN-002 (and UC-TEN-006).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: gateway ingest `gen` under tenant-a, flush; query-api/tenant-b
  → success + 0 series; query-api/tenant-a → success + ≥1 series.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/q08-tenant-b.json`](evidence/q08-tenant-b.json) (empty), [`evidence/q08-tenant-a.json`](evidence/q08-tenant-a.json) (control).

## Issues

None.

## Notes

`.no-compose` marker; built via `harness/run-eg.sh`. Isolation, not
absence: the tenant-a control proves the data is present and durable.
