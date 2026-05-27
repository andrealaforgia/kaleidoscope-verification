# S11 — cross-signal-resource-symmetry

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

Traces, logs, and metrics emitted from the same Spark-instrumented app carry an identical Resource attribute set on each signal. The harness emits one trace, one tracing log, and one counter, then `diff`s the resource attribute sets extracted from `resourceSpans`, `resourceLogs`, and `resourceMetrics` in the otelcol-sink capture.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **S11**.
- External contract anchor: [`docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md) and the OTel SDK conventions on shared Resource across signals.

## Verification

- Status: `broken` (suspected flake — same shape as the
  closed-as-flake issues 006/007 on A10/S03/A15)
- Last verified: 2026-05-27 UTC at HEAD (`d782482`) — broken:
  aperture container never reached `/readyz=200` within 180 s
  across two consecutive runs. Cycle 12 of the overnight loop.
  Same docker-pressure pattern; cold retry next cycle expected
  to recover.
- Earlier satisfaction: 2026-05-11 at HEAD `3a18514` and
  across many later cycles.
- Method: driven by the **spark-consumer** fixture under
  `harness/spark-consumer/`. The fixture is built once via
  `docker compose --profile fixture build spark-consumer` and
  cached; this runner invokes a scenario on the compose network so
  the SDK's OTLP exporter reaches aperture. After the consumer
  exits cleanly (which flushes the in-flight batch via SparkGuard's
  Drop), the runner waits 3 s for the forwarding chain to settle,
  then `jq`-asserts on the otelcol-sink file-exporter capture.
  Uses the consumer scenario `s11-cross-signal-symmetry` which emits all three signals from one Spark.

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
