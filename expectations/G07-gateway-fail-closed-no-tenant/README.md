# G07 — gateway-fail-closed-no-tenant

## Surface

`crates/kaleidoscope-gateway` binary, tenant resolution on ingest.

## Behaviour

With NO default tenant configured, a record that carries no resource
`tenant.id` is REFUSED, not silently dropped into a void: the gateway
returns a sink error (`no tenant: record carries no tenant.id resource
attribute and no default_tenant is configured; refusing per ADR-0041
Decision 2`) and the OTLP export fails. Control: the SAME record IS
accepted when `KALEIDOSCOPE_DEFAULT_TENANT` is set, so the refusal is the
no-tenant condition, not a broken gateway. Covers UC-GWTEN-003.

## Source

- External contract anchor: gateway tenant resolution (ADR-0041 Decision
  2 — refuse rather than default-into-a-void).
- Use-case anchor: `kaleidoscope-usecases` UC-GWTEN-003.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`5713222`).
- Method: gateway with no default tenant + a no-`tenant.id` log →
  telemetrygen fails (exit 1), gateway surfaces the no-tenant refusal;
  with `KALEIDOSCOPE_DEFAULT_TENANT=acme` the same log is accepted
  (exit 0).

## Evidence

- [`evidence/G07.stdout.txt`](evidence/G07.stdout.txt) — exit codes.
- [`evidence/none.telemetrygen.txt`](evidence/none.telemetrygen.txt) — the refusal reason.
- [`evidence/none.gateway.stderr.txt`](evidence/none.gateway.stderr.txt).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-gateway.sh`. Completes UC-GWTEN
(5/5) with EG04 (explicit routing), LQ02 (default fallback), Q08/LQ07/TQ05
(read isolation). The fail-closed-no-silent-void invariant is the tenancy
safety net.
