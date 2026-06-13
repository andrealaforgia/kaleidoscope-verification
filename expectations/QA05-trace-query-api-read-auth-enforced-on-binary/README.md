# QA05 — trace-query-api-read-auth-enforced-on-binary

## Surface

Read path / security. The deployed `trace-query-api` binary's per-request
bearer auth on BOTH its routes (the traces analogue of QA02/QA03).

## Behaviour

The trace API exposes two routes that share one auth seam (lib.rs: "auth shared
by BOTH the window route and the lookup-by-id route"), so a wiring slip could
guard one and miss the other. Booted with a complete read-auth config (audience
`kaleidoscope-query`, catalogue `harness-tenant`) and no env tenant, both routes
are guarded:

- window `GET /api/v1/traces?service=&start=&end=` — valid `kaleidoscope-query`
  bearer → `200`; no bearer / ingest-audience / expired / malformed → `401`.
- by-id `GET /api/v1/traces/by_id?trace_id=<32-hex>` — valid bearer → `200`
  (non-`401`); no bearer → `401`; ingest-audience → `401`.

No-bearer-bypass (R3) and the audience fence (DD6) both hold on each route; the
lookup-by-id sibling route is not an unguarded back door.

## Source

- kaleidoscope `read-path-query-api-auth-v0` slice 3c (`6fb7f9a`):
  `crates/trace-query-api/src/main.rs` (resolves `KALEIDOSCOPE_TRACE_QUERY_AUTH_*`,
  calls `router_with_auth(store, tenant, auth)`) + `src/lib.rs`
  (`TRACES_ROUTE` + `TRACES_BY_ID_ROUTE` share the auth) +
  `crates/query-http-common` (the shared resolver).
- Contract anchor: ADR-0074 DD1/DD3/DD6; ADR-0053 (by_id route).

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `c6f95e1` (code `6fb7f9a`). Codes:
  window `valid=200`, `nobearer=401`, `ingest=401`, `expired=401`,
  `malformed=401`; by_id `valid=200`, `nobearer=401`, `ingest=401`.
- Transition-proof: RED (naming the breach + route) if any adversarial bearer is
  served non-`401` on either route — in particular if `by_id` is unguarded.
- Method: `harness/run-trace-query-api.sh` builds `Dockerfile.trace-query-api`;
  the runner boots it with the valid auth config + mounted secret/catalogue on
  port `19093:9092`, then probes both routes with valid / no-bearer / ingest /
  expired / malformed bearers.

## Notes

`.no-compose`: QA05 only boots `trace-query-api` (auth is decided before the
store, so an empty store suffices; valid → `200` with an empty/absent result).
Completes the read-auth binary-enforcement sweep across all three read APIs:
QA02 (query-api), QA03 (log-query-api), QA05 (trace-query-api); QA04 is the
env-tenant-seeded no-bearer-bypass + isolation deep-dive on query-api.
