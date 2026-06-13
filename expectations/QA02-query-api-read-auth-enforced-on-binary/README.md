# QA02 — query-api-read-auth-enforced-on-binary

## Surface

Read path / security. The deployed `query-api` binary's per-request bearer
auth (the first read API whose binary actually constructs and enforces a
`Validator`).

## Behaviour

Booted with a complete read-auth config (`KALEIDOSCOPE_QUERY_AUTH_ISSUER=
kaleidoscope-harness`, `_AUDIENCE=kaleidoscope-query`, `_SECRET_FILE`, a
`_CATALOGUE` holding `harness-tenant`) and **no** env tenant, the deployed
`query-api` enforces bearer auth on `/api/v1/query_range`:

- a **valid** `kaleidoscope-query`-audience bearer for the catalogued tenant is
  served `200` (`status:success`; the query scopes to the token's tenant — an
  empty store returns an empty result, still `200`);
- **no bearer** → `401`, never `200` — the no-bearer-bypass property (R3): an
  auth-enabled listener must not fall through to any env tenant without a
  bearer;
- an **ingest-audience** token (`kaleidoscope-cluster`) → `401` — the audience
  fence (DD6): the read path accepts only `kaleidoscope-query`;
- **wrong issuer**, **uncatalogued tenant**, **unknown role**, **expired**,
  **forged signature** (mutated + signed-under-attacker-key), **alg=none**, and
  **malformed** bearers → `401` each.

Every refusal is `401` with `WWW-Authenticate: Bearer` (RFC 6750) and a typed
`{"status":"error","error":"<reason>"}` body that carries no tenant data and no
secret. aegis emits exactly one structured decision line per request (`allow`
once; `deny` with `reason` ∈ {`missing_claim`, `wrong_audience`,
`wrong_issuer`, `unknown_tenant`, `unknown_role`, `expired`,
`invalid_signature`, `malformed`}).

This is the first slice where a read API's deployed binary wires
`router_with_auth(Some(validator))` (slices 1–2 left all three binaries on the
`None` arm). It makes the read-auth path black-box reachable and proves it
enforces, not merely compiles.

## Source

- kaleidoscope `read-path-query-api-auth-v0` slice 3a (`c389a23`):
  `crates/query-api/src/main.rs` (`router_with_auth(store, tenant, auth,
  static_dir)` with `auth` resolved from env) +
  `crates/query-http-common/src/lib.rs`
  (`resolve_request_tenant_or_refuse`, the 3-arm no-`else env_tenant` body).
- Contract anchor: ADR-0074 DD1/DD3 (bearer is the per-request tenant
  authority) / DD5 (one decision line) / DD6 (`kaleidoscope-query` audience
  fence). aegis `Validator::validate_with_subject`.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `c389a23` (slice 3a). Response codes:
  `valid=200`, `nobearer=401`, `ingest=401`, `wrongiss=401`, `ghost=401`,
  `badrole=401`, `expired=401`, `wrongkey=401`, `forged=401`, `algnone=401`,
  `malformed=401`. `valid` body `status:success`, `result` empty (empty store).
  No-bearer `401` carries `www-authenticate: Bearer error="invalid_token",
  error_description="missing_claim"`. The aegis decision log shows one line per
  request with the matching typed reason (allow ×1; deny reasons as above).
- Transition-proof: RED (and names the breach) if any adversarial bearer — above
  all **no-bearer** or the **ingest-audience** token — is served `200`.
- Method: `harness/run-query-api.sh` builds `Dockerfile.query-api` from the HEAD
  snapshot; the runner mints the bearer battery host-side with
  `harness/mint-ingest-jwt.sh` (HS256 over `harness/jwt.secret`, audience/issuer/
  tenant/role/ttl overrides) plus a hand-crafted `alg=none` and a
  signed-under-attacker-key forgery, boots the image with the valid auth config
  + mounted secret/catalogue, polls readiness, then probes `/api/v1/query_range`
  with each bearer and asserts the codes, the positive body, the RFC 6750
  header, and that no refusal body leaks secret material.

## Evidence

- [`evidence/QA02.stdout.txt`](evidence/QA02.stdout.txt) — the `code_*` lines.
- `evidence/body-*.json`, `evidence/hdr-*.txt` — per-bearer body + headers.
- [`evidence/query-api.stderr.txt`](evidence/query-api.stderr.txt) — the
  one-line-per-request aegis decision audit.

## Notes

`.no-compose`: QA02 only boots `query-api` (no gateway / data seeding — the
auth attack is decided before the store, so an empty store suffices; the valid
positive control returns `200` with an empty result). The companion QA01
verifies the refuse-to-start path for a *broken* auth config. The log-query-api
and trace-query-api binaries still call the plain `router(..)` (auth `None`) at
`c389a23`, so this binary-enforcement contract is query-api-only until a later
slice wires them.
