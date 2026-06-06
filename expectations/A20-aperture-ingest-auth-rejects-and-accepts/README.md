# A20 — aperture-ingest-auth-rejects-and-accepts

## Surface

`crates/aperture` binary, OTLP/HTTP ingest door. Operator-facing.

## Behaviour

With a complete, valid `[aperture.security.auth.jwt]` config aperture
starts and enforces the HS256 JWT at the door, before any body work:

- OTLP/HTTP ingest with NO bearer → `401` + `WWW-Authenticate: Bearer
  error="invalid_token", error_description="missing_claim"`;
- ingest with a BOGUS bearer → `401`;
- ingest with a VALID HS256 JWT for a catalogued tenant clears the auth
  door (the `application/json` probe then returns `415` at the
  content-type gate — auth is no longer the blocker);
- a real OTLP/protobuf batch carrying the valid bearer is ACCEPTED
  (telemetrygen exit 0), while the same batch WITHOUT a bearer is refused
  `401`.

The identical request differing only by the bearer flips `401` → not-401,
isolating auth as the gate. Covers the enforcement half of **UC-AUTH-002**
(unauthenticated ingest rejected).

## Source

- External contract anchor: `aegis-ingest-auth-v0`, ADR-0068 DD2/DD5,
  deliver `7f72db8`; aperture shared `authenticate()` step; aegis HS256
  validator (claims `iss`/`aud`/`exp`/`tenant_id`/`kaleidoscope_role`).
- Use-case anchor: `kaleidoscope-usecases` UC-AUTH-002.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`9817ec9`).
- Method: run aperture with a valid auth config (mounted HS256 secret +
  tenant catalogue); curl the door with no/bogus/valid bearer; craft the
  valid token with the same secret; confirm 401 + challenge on reject and
  an accepted OTLP/protobuf batch on the valid bearer.

## Evidence

- [`evidence/observation.txt`](evidence/observation.txt) — noauth/bogus/valid codes + telemetrygen exits.
- [`evidence/noauth.headers`](evidence/noauth.headers) — the `WWW-Authenticate: Bearer` challenge.
- [`evidence/tg-accept.out`](evidence/tg-accept.out) (accepted), [`evidence/tg-reject.out`](evidence/tg-reject.out) (401).

## Issues

None.

## Notes

`.no-compose`, A17-style self-contained run. Tenant ripple (TenantScoped
tagging through the sink) is a type-level guarantee not observable through
the stub sink; credited to the implementer's in-suite tests — see
`known-gaps.md` N29. Companion to **A19** (refuse-to-start).
