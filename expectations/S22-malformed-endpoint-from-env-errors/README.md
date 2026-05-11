# S22 — malformed-endpoint-from-env-errors

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

Setting `OTEL_EXPORTER_OTLP_ENDPOINT` to a malformed URL (and not setting `with_endpoint(...)`) causes spark::init to return `Err(InvalidEndpoint)` with the same error shape as the builder-side equivalent (S08).

## Source

- Inter-session feed (other claude session, 2026-05-06): item **S22**.
- External contract anchor: [`docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md) for the endpoint validation; the env-var path is part of the OTEL_EXPORTER_OTLP_* set Spark honours.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-11 UTC at HEAD.
- Kaleidoscope SHA: `3a18514d51711bc1e9a611f44eb3e86f42ec353e`
- Method: driven by the **spark-consumer** fixture under
  `harness/spark-consumer/`. The fixture is built once via
  `docker compose --profile fixture build spark-consumer` and
  cached; this runner invokes a scenario on the compose network so
  the SDK's OTLP exporter reaches aperture. After the consumer
  exits cleanly (which flushes the in-flight batch via SparkGuard's
  Drop), the runner waits 3 s for the forwarding chain to settle,
  then `jq`-asserts on the otelcol-sink file-exporter capture.
  Init-side check, no aperture (`.no-compose` marker). The env var is set on the consumer's `docker run -e OTEL_EXPORTER_OTLP_ENDPOINT=this-is-not-a-valid-url ...` invocation.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/spark-consumer-build.txt`](evidence/spark-consumer-build.txt) — fixture build log.
- [`evidence/consumer.stdout.txt`](evidence/consumer.stdout.txt) — structured outcome line.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's stderr during the run.
- [`evidence/otlp-received.jsonl`](evidence/otlp-received.jsonl) — otelcol-sink's file-exporter capture; the `jq` filter cited in `runner.stdout.txt` extracts the asserted attribute(s) from this file.

## Issues

None.

## Notes

This expectation rides the same spark-consumer fixture as S01.
Adding more S/E coverage is now pattern repetition.
