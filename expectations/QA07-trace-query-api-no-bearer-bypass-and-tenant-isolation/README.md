# QA07 — trace-query-api-no-bearer-bypass-and-tenant-isolation

## Surface

Read path / security. The load-bearing no-bearer-bypass (R3) and cross-tenant
isolation via the bearer, on the deployed trace-query-api (the traces analogue
of QA04/QA06).

## Behaviour

The binary runs with a valid env tenant whose **traces are seeded**, so a bypass
would leak real spans.

1. The gateway (`KALEIDOSCOPE_DEFAULT_TENANT=tenant-a`) ingests traces for a
   known service; only `tenant-a` has spans.
2. trace-query-api on the same `/data` with read-auth configured (audience
   `kaleidoscope-query`, catalogue `{tenant-a, tenant-b}`) **and**
   `KALEIDOSCOPE_TRACE_QUERY_TENANT=tenant-a`.
3. `GET /api/v1/traces?service=<svc>`:
   - **no bearer** → `401`, **0 spans** (no fall-through to `tenant-a`'s spans);
   - **expired bearer** → `401`, **0 spans**;
   - **tenant-a bearer** → `200`, **10 spans** (valid bearer reads the token
     tenant's spans);
   - **tenant-b bearer** → `200`, **0 spans** (a VALID token scoped to
     `tenant-b`, which has no spans: the bearer's tenant governs scope).

## Source

- kaleidoscope `read-path-query-api-auth-v0` slice 3c (`6fb7f9a`), shared
  `query-http-common::resolve_request_tenant_or_refuse` (R3).
- Contract anchor: ADR-0074 DD3/R3; ADR-0048 (window arm). Completes implementer
  message 035's load-bearing challenge across all three read endpoints.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `c6f95e1` (code `6fb7f9a`).
  `code_nobearer=401 rows_nobearer=0`; `code_expired=401 rows_expired=0`;
  `code_tenanta=200 rows_tenanta=10`; `code_tenantb=200 rows_tenantb=0`.
- Transition-proof: RED if no-bearer/expired returns ANY span, or if the
  tenant-b bearer sees tenant-a's spans.
- Method: `harness/run-eg.sh` builds gateway + trace-query-api; the runner seeds
  `tenant-a` traces via telemetrygen, boots trace-query-api with auth + a
  two-tenant catalogue + `KALEIDOSCOPE_TRACE_QUERY_TENANT=tenant-a`, and probes
  the window route with no-bearer / expired / tenant-a / tenant-b bearers.

## Notes

`.no-compose`: QA07 manages its own gateway + trace-query-api containers.
Completes the env-tenant-seeded no-bearer-bypass + isolation sweep: QA04
(metrics), QA06 (logs), QA07 (traces). The bearer-scoped behaviour is governed
by the shared `query-http-common` resolver, proven not to fall through to the
env tenant on any of the three read APIs.
