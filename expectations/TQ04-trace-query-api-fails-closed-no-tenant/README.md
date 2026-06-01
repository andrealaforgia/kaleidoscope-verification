# TQ04 — trace-query-api-fails-closed-no-tenant

## Surface

trace-query-api (Ray traces read HTTP service). Operator-facing.

## Behaviour

Given trace-query-api is started without `KALEIDOSCOPE_TRACE_QUERY_TENANT`
When it runs the Earned-Trust probe (wire → probe → use)
Then it fails closed: it refuses to bind the listener, exits non-zero,
and emits a STRUCTURED JSON `health.startup.refused` event at `ERROR`
level on stderr (fields include `reason`, naming
`KALEIDOSCOPE_TRACE_QUERY_TENANT ... (fail-closed)`) BEFORE the exit.

## Source

- Fail-closed tenancy (ADR-0042 DD9, Earned-Trust) + the structured
  lifecycle event from read-api-tracing-subscriber-v0 (feat `2663eb5`,
  `query_http_common::init_tracing`).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`2663eb5`). GREEN at first
  attempt: `exit=1`; observed stderr line
  `{"level":"ERROR","event":"health.startup.refused","reason":"KALEIDOSCOPE_TRACE_QUERY_TENANT is unset or empty (fail-closed)"}`.
- Method: dockerised harness via `harness/run-trace-query-api.sh`
  (catalogue-authored `harness/Dockerfile.trace-query-api`). The binary
  is run against a fresh `/data` with NO tenant var; the assertion
  checks a non-zero exit and, via `jq` on the JSON event line, that
  `event==health.startup.refused`, `level==ERROR`, and the reason names
  the tenant fail-closed.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `2663eb5`.
- [`evidence/trace-query-api.stderr.txt`](evidence/trace-query-api.stderr.txt)
  — the structured JSON refusal event (no longer empty; cf. issue 005,
  now resolved).
- [`evidence/TQ04.stdout.txt`](evidence/TQ04.stdout.txt) — exit code + stderr.

## Issues

None. Part of the black-box evidence that closed
[issue 005](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md).

## Notes

The trace-tier sibling of Q01 (query-api) and LQ06 (log-query-api), all
verified at `2663eb5`.
