# E03 — round-trip-metric

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

A counter incremented via `opentelemetry::global::meter(...).u64_counter(...).build().add(1, &[])` after spark::init reaches aperture as an OTLP MetricsRequest after the consumer's clean shutdown flushes the batch.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **E3**.
- External contract anchor: OTel Rust SDK Metrics API (0.27.x); Spark passes the global Meter through unchanged.

## Verification

- Status: `satisfied` — re-flipped 2026-06-06 at HEAD `8620439` via the standard OTLP env auth path (`OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <jwt>`), which the Spark exporter already honours (upstream, ADR-0069 amendment). The compose aperture carries the matching auth block + secret/catalogue (N29). The earlier "blocked on Spark ingest-auth" was overstated: only the *programmatic* SparkConfig knob was missing; the env path was always a valid key.
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
  Verified by the presence of a `resourceMetrics` payload in the otelcol-sink capture with the matching `service.name`.

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
