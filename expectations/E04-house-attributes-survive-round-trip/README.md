# E04 — house-attributes-survive-round-trip

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

All four Kaleidoscope-house Resource attributes (`service.name`, `tenant.id`, `feature_flag.*`, `experiment.id`) configured on `SparkConfig` are still present, intact, on the Resource observed at the otelcol-sink downstream of aperture. End-to-end propagation contract.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **E4**.
- External contract anchor: [`docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md).

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
  Invoked with `--require-tenant-id --tenant-id acme-prod-E04 --feature-flag rollout=staged --experiment-id exp-E04-xyz`. All four resource keys are asserted by name on the captured Resource.

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
