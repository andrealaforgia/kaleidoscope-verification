# EG04 — gateway-explicit-tenant-id-routing

## Surface

`crates/kaleidoscope-gateway` → Pulse → `crates/query-api`. Operator-facing.

## Behaviour

A record carrying an explicit OTLP resource `tenant.id` is routed to THAT
tenant, overriding the gateway's configured default. The gateway runs
with `KALEIDOSCOPE_DEFAULT_TENANT=acme`; a metric tagged
`tenant.id=globex` lands under globex (visible to a globex query-api,
invisible to an acme query-api). Covers UC-GWTEN-001.

## Source

- External contract anchor: gateway per-record tenant resolution
  (explicit resource `tenant.id` > configured default).
- Use-case anchor: `kaleidoscope-usecases` UC-GWTEN-001.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`b058a34`).
- Method: gateway default=acme; ingest `gen` with `tenant.id=globex`;
  query as globex → 1 series, query as acme → 0 series.

## Evidence

- [`evidence/globex.json`](evidence/globex.json) (present), [`evidence/acme.json`](evidence/acme.json) (empty).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. Complements EG03 (series
identity), Q08 (cross-tenant read isolation, UC-GWTEN-004) and LQ02 (the
default-tenant fallback, UC-GWTEN-002). UC-GWTEN-003 (fail-closed with no
default tenant) is the remaining gap.
