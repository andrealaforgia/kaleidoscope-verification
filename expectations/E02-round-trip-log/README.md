# E02 — round-trip-log

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

A tracing::info!(target="<app>", ...) emitted from a Spark-instrumented app reaches aperture as an OTLP LogRecord. Spark wires `opentelemetry-appender-tracing` per ADR-0017 to bridge tracing events to OTel logs.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **E2**.
- External contract anchor: [`docs/product/architecture/adr-0017-spark-logs-emission-via-tracing-appender.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0017-spark-logs-emission-via-tracing-appender.md).

## Verification

- Status: `pending` (blocked: Spark SDK has no ingest-auth knob; cannot authenticate to the now-auth-mandatory aperture — see known-gaps.md N29; was satisfied pre-auth at 545a2ba)
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
  Verified by the presence of a `resourceLogs` payload in the otelcol-sink capture with the matching `service.name` on the Resource.

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
