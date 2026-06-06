# G06 — gateway-healthz-serving

## Surface

`crates/kaleidoscope-gateway` binary, `/healthz` + `/readyz` endpoints.

## Behaviour

Once live, the gateway's `/healthz` returns 200 (liveness; body `ok`) and
`/readyz` returns 200 READY. Covers UC-GWHEALTH-002 and confirms the
readiness gate that e2e tests rely on (UC-GWHEALTH-006).

## Source

- External contract anchor: gateway health/readiness endpoints.
- Use-case anchor: `kaleidoscope-usecases` UC-GWHEALTH-002 (and -006).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`bb33b95`).
- Method: boot the gateway to `listener_bound`; `GET /healthz` → 200 with
  a non-empty body; `GET /readyz` → 200.

## Evidence

- [`evidence/G06.stdout.txt`](evidence/G06.stdout.txt) — codes.
- [`evidence/healthz.body`](evidence/healthz.body), [`evidence/readyz.body`](evidence/readyz.body).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-gateway.sh`. The `/healthz` body is
`ok` (HTTP liveness convention); the UC's "SERVING" wording is the gRPC
health vocabulary — the 200 liveness contract is what is asserted here.
