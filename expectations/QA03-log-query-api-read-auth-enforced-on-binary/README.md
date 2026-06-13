# QA03 — log-query-api-read-auth-enforced-on-binary

## Surface

Read path / security. The deployed `log-query-api` binary's per-request bearer
auth (the logs analogue of QA02).

## Behaviour

Booted with a complete read-auth config (`KALEIDOSCOPE_LOG_QUERY_AUTH_ISSUER=
kaleidoscope-harness`, `_AUDIENCE=kaleidoscope-query`, `_SECRET_FILE`, a
`_CATALOGUE` holding `harness-tenant`) and **no** env tenant, the deployed
`log-query-api` enforces bearer auth on `GET /api/v1/logs`:

- a **valid** `kaleidoscope-query`-audience bearer for the catalogued tenant is
  served `200` (the query scopes to the token's tenant; an empty store returns
  `[]`, still `200`);
- **no bearer** → `401`, never `200` (no-bearer-bypass R3 — no env-tenant
  fall-through);
- an **ingest-audience** token (`kaleidoscope-cluster`) → `401` (audience fence
  DD6);
- **wrong issuer**, **uncatalogued tenant**, **unknown role**, **expired**,
  **forged signature** (mutated + signed-under-attacker-key), **alg=none**, and
  **malformed** bearers → `401` each.

The `401` carries `WWW-Authenticate: Bearer` (RFC 6750). This proves slice 3b
wired `router_with_auth(Some(validator))` into the LOG binary's router (not just
query-api's), reusing the shared `query-http-common` capability, and that every
log route is guarded.

## Source

- kaleidoscope `read-path-query-api-auth-v0` slice 3b (`d6a2094`):
  `crates/log-query-api/src/main.rs` (resolves `KALEIDOSCOPE_LOG_QUERY_AUTH_*`,
  calls `router_with_auth(store, tenant, auth)`) +
  `crates/query-http-common/src/lib.rs` (`resolve_request_tenant_or_refuse`,
  shared with query-api).
- Contract anchor: ADR-0074 DD1/DD3/DD5/DD6. In-process counterpart:
  `tests/slice_10_auth_config_reject.rs`.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `d6a2094` (slice 3b). Codes:
  `valid=200` (body `[]`), `nobearer=401`, `ingest=401`, `wrongiss=401`,
  `ghost=401`, `badrole=401`, `expired=401`, `wrongkey=401`, `forged=401`,
  `algnone=401`, `malformed=401`. No-bearer `401` carries
  `www-authenticate: Bearer error="invalid_token",
  error_description="missing_claim"`.
- Transition-proof: RED (naming the breach) if any adversarial bearer — above
  all no-bearer or the ingest-audience token — is served `200` on the log API.
- Method: `harness/run-log-query-api.sh` builds `Dockerfile.log-query-api` from
  the HEAD snapshot; the runner mints the same bearer battery as QA02 host-side,
  boots the log image with the valid auth config + mounted secret/catalogue on
  port `19092:9091`, polls readiness, probes `/api/v1/logs` with each bearer and
  asserts the codes, the positive body shape, the RFC 6750 header, and no secret
  leak.

## Notes

`.no-compose`: QA03 only boots `log-query-api` (no gateway / data seeding — the
auth decision precedes the store; the valid positive control returns `200` with
`[]`). Companion: QA02 (query-api enforcement), QA01 (query-api refuse-to-start).
At `d6a2094` the trace-query-api binary still calls plain `router(..)` (auth
`None`); its enforcement contract opens when a later slice wires it.
