# S03 — tenant-id-on-resource-when-required

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

With `require_tenant_id()` AND `with_tenant_id(id)`, the Resource carries an attribute `tenant.id` equal to the configured id. This is one of the four house attributes the Kaleidoscope conventions add on top of OTel's standard set.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **S3**.
- External contract anchor: [`docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md) for the tenant.id house attribute.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-27 UTC at HEAD (`34131c9`).
  `tenant.id observed: acme-prod-S03` on the otelcol-sink
  capture. Cycle 6's failure was confirmed flake (cold retry
  in cycle 7 GREEN at first attempt); issue 007 closed.
- Previously satisfied at HEAD `3a18514` and across many
  subsequent cycles.
- Method: driven by the **spark-consumer** fixture under
  `harness/spark-consumer/`. The fixture is built once via
  `docker compose --profile fixture build spark-consumer` and
  cached; this runner invokes a scenario on the compose network so
  the SDK's OTLP exporter reaches aperture. After the consumer
  exits cleanly (which flushes the in-flight batch via SparkGuard's
  Drop), the runner waits 3 s for the forwarding chain to settle,
  then `jq`-asserts on the otelcol-sink file-exporter capture.
  The consumer scenario `s01-init-and-emit-trace` was invoked with `--require-tenant-id --tenant-id acme-prod-S03`.

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
