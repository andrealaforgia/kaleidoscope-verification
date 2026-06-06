# E07 — spark-programmatic-bearer-auth

## Surface

`crates/spark` SDK (`SparkConfig::with_bearer_token`) → aperture →
otelcol-sink. Integrator-facing, the programmatic ingest-auth path.

## Behaviour

The programmatic ingest-auth knob delivered by `spark-ingest-auth-v0`
(`742536b`): `SparkConfig::with_bearer_token(token)` attaches
`authorization: Bearer <token>` metadata to all three OTLP exporters, so a
code-configured (not env-configured) SDK user authenticates to aperture
and a span round-trips to otelcol-sink, with aperture logging
`decision=allow ingest_traces tenant_id=harness-tenant role=operator`.

Negative control: the SAME emission WITHOUT a token produces no span at
the sink (denied), so the round-trip is the token's doing, not an open
door. Complements E01-E04 (the `OTEL_EXPORTER_OTLP_HEADERS` env path).

## Source

- External contract anchor: `spark-ingest-auth-v0`, deliver `742536b`
  (`SparkConfig::with_bearer_token` + `with_metadata` on all exporters).
- Use-case anchor: `kaleidoscope-usecases` UC-AUTH-002 (programmatic half).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`742536b`).
- Method: run the spark-consumer with `--auth-token <jwt>` (no env
  header) → span lands at otelcol-sink + aperture `decision=allow`; run
  without a token → no span (denied).

## Evidence

- [`evidence/consumer.stdout.txt`](evidence/consumer.stdout.txt) — authenticated emission outcome.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — `decision=allow` for the bearer.
- [`evidence/noauth.stdout.txt`](evidence/noauth.stdout.txt) — the no-token negative control.

## Issues

None.

## Notes

`.no-compose` is NOT set — E07 uses the compose aperture stack (with the
N29 auth block + secret/catalogue). The token is minted by
`harness/mint-ingest-jwt.sh`; the spark-consumer gained an `--auth-token`
arg that calls `with_bearer_token`. The secret-never-logged invariant
(redacting `BearerToken`) is credited to the implementer's in-suite test
`oncall_bearer_token_value_does_not_appear_in_request_body` (X01).
