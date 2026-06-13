# QA04 — query-api-no-bearer-bypass-and-tenant-isolation

## Surface

Read path / security. The load-bearing no-bearer-bypass property (R3) and
cross-tenant isolation via the bearer, on the deployed query-api.

## Behaviour

Strengthens QA02: the binary runs **with a valid env tenant whose data is
seeded**, so a bypass would return real rows, not merely a `200` against an
empty store.

1. The gateway (`KALEIDOSCOPE_DEFAULT_TENANT=tenant-a`) ingests one `gen`
   metric; only `tenant-a` has data.
2. query-api runs on the same `/data` with read-auth configured (audience
   `kaleidoscope-query`, catalogue `{tenant-a, tenant-b}`) **and**
   `KALEIDOSCOPE_QUERY_TENANT=tenant-a` — the env tenant DOES have rows.
3. `/api/v1/query_range?query=gen`:
   - **no bearer** → `401`, **0 rows** (`status:error`). The load-bearing
     assertion: auth-on must not fall through to the env tenant even though
     `tenant-a` has data. A `200` with `tenant-a`'s `gen` here would be the
     no-bearer-bypass (R3) bug.
   - **expired bearer** → `401`, **0 rows** (a present-but-invalid token also
     does not fall through).
   - **tenant-a bearer** → `200 success`, **1 series** (a valid bearer reads the
     token tenant's data — positive control).
   - **tenant-b bearer** → `200 success`, **0 series** (a VALID token, but it
     scopes to `tenant-b` which has no data: the bearer's tenant governs scope,
     not the env tenant — cross-tenant isolation via bearer).

No bearer-token substring appears in any response body or the server log
(redaction).

## Source

- kaleidoscope `read-path-query-api-auth-v0` (`6fb7f9a`),
  `crates/query-http-common/src/lib.rs` `resolve_request_tenant_or_refuse`
  (the 3-arm body with no `else env_tenant` fall-through, R3).
- Contract anchor: ADR-0074 DD3 (the bearer is the per-request tenant
  authority) / R3 (no-bearer-bypass). Directly answers implementer message 035's
  load-bearing challenge ("a bad-token request returning ANY row is the bug").

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `c6f95e1` (code `6fb7f9a`; the two
  commits above are docs only). `code_nobearer=401 rows_nobearer=0`;
  `code_expired=401 rows_expired=0`; `code_tenanta=200 rows_tenanta=1
  status=success`; `code_tenantb=200 rows_tenantb=0 status=success`.
- Transition-proof: RED (naming the breach) if the no-bearer or expired request
  returns ANY row, or if the tenant-b bearer sees tenant-a's `gen`.
- Method: `harness/run-eg.sh` builds the gateway + query-api images; the runner
  seeds `tenant-a` via telemetrygen → gateway, boots query-api with auth + a
  two-tenant catalogue fixture + `KALEIDOSCOPE_QUERY_TENANT=tenant-a`, mints
  `tenant-a` / `tenant-b` / expired bearers, and asserts the codes + row counts
  + token-absence.

## Notes

`.no-compose`: QA04 manages its own gateway + query-api containers (it needs the
seeding gateway but not the full compose stack). Companion: QA02 (the empty-store
enforcement battery), QA03 (logs), QA05 (traces). The same env-tenant + seeded
no-bearer-bypass test on the log and trace binaries is the next increment.
