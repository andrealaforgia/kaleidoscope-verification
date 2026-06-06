# E01 — round-trip-trace

## Surface

Spark (auto-instrumentation SDK) / end-to-end. Integrator-facing.

## Behaviour

A Spark-instrumented app emits one span via `opentelemetry::global::tracer`. The span round-trips through aperture and arrives at the downstream sink (here, the otelcol-sink). Verified by extracting the span's `name` from `resourceSpans[].scopeSpans[].spans[]` in the captured OTLP.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **E1**.
- External contract anchor: [`docs/feature/aperture/slices/slice-03-traces.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/feature/aperture/slices/slice-03-traces.md) for aperture's traces contract; S01 covers the Spark-side ack.

## Verification

- Status: `satisfied` — re-flipped 2026-06-06 at HEAD `8620439` via the standard OTLP env auth path (`OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <jwt>`), which the Spark exporter already honours (upstream, ADR-0069 amendment). The compose aperture carries the matching auth block + secret/catalogue (N29). The earlier "blocked on Spark ingest-auth" was overstated: only the *programmatic* SparkConfig knob was missing; the env path was always a valid key.
- Last verified: 2026-05-27 UTC at HEAD (`29f109b`).
  `span observed: spark-consumer-emit-trace` — GREEN at the
  fourth attempt this cycle, after three consecutive
  `/readyz=200` 180 s flakes. Notably A11 and S01 GREEN at
  first attempt on the same compose stack between the three
  E01 fails; no aperture-wide regression, just a sticky local
  flake. Same disposition as closed issues 006/007.
- Earlier satisfaction: 2026-05-11 at `3a18514` and across many
  later cycles.
- Method: driven by the **spark-consumer** fixture under
  `harness/spark-consumer/`. The fixture is built once via
  `docker compose --profile fixture build spark-consumer` and
  cached; this runner invokes a scenario on the compose network so
  the SDK's OTLP exporter reaches aperture. After the consumer
  exits cleanly (which flushes the in-flight batch via SparkGuard's
  Drop), the runner waits 3 s for the forwarding chain to settle,
  then `jq`-asserts on the otelcol-sink file-exporter capture.
  

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
