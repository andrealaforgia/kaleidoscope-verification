# QA06 — log-query-api-no-bearer-bypass-and-tenant-isolation

## Surface

Read path / security. The load-bearing no-bearer-bypass (R3) and cross-tenant
isolation via the bearer, on the deployed log-query-api (the logs analogue of
QA04).

## Behaviour

The binary runs with a valid env tenant whose **logs are seeded**, so a bypass
would leak real records.

1. The gateway (`KALEIDOSCOPE_DEFAULT_TENANT=tenant-a`) ingests logs carrying a
   known body needle; only `tenant-a` has logs.
2. log-query-api on the same `/data` with read-auth configured (audience
   `kaleidoscope-query`, catalogue `{tenant-a, tenant-b}`) **and**
   `KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-a`.
3. `GET /api/v1/logs?...&body_contains=<needle>`:
   - **no bearer** → `401`, **0 records** (no fall-through to `tenant-a`'s logs);
   - **expired bearer** → `401`, **0 records**;
   - **tenant-a bearer** → `200`, **6 records** (valid bearer reads the token
     tenant's logs);
   - **tenant-b bearer** → `200`, **0 records** (a VALID token scoped to
     `tenant-b`, which has no logs: the bearer's tenant governs scope).

## Source

- kaleidoscope `read-path-query-api-auth-v0` (`6fb7f9a`), shared
  `query-http-common::resolve_request_tenant_or_refuse` (R3, no `else
  env_tenant`).
- Contract anchor: ADR-0074 DD3/R3. Answers implementer message 035's
  load-bearing challenge for the log endpoint.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `c6f95e1` (code `6fb7f9a`).
  `code_nobearer=401 rows_nobearer=0`; `code_expired=401 rows_expired=0`;
  `code_tenanta=200 rows_tenanta=6`; `code_tenantb=200 rows_tenantb=0`.
- Transition-proof: RED if no-bearer/expired returns ANY record, or if the
  tenant-b bearer sees tenant-a's needle.
- Method: `harness/run-eg.sh` builds gateway + log-query-api; the runner seeds
  `tenant-a` logs via telemetrygen, boots log-query-api with auth + a two-tenant
  catalogue + `KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-a`, and probes
  `/api/v1/logs` with no-bearer / expired / tenant-a / tenant-b bearers.

## Notes

`.no-compose`: QA06 manages its own gateway + log-query-api containers.
Companion: QA04 (metrics), QA07 (traces) — the same env-tenant-seeded
no-bearer-bypass + isolation test across all three read endpoints.
