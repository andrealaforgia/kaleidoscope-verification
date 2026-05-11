# S01 — init-canonical-config-emits-span

## Surface

Spark (auto-instrumentation SDK). Integrator-facing.

## Behaviour

spark::init with a canonical config returns Ok(SparkGuard); a span emitted via opentelemetry::global::tracer reaches aperture and arrives at otelcol-sink via the forwarding chain.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **S1**.
- External contract anchor:
  [`docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0011-spark-public-api-and-crate-layout.md)
  for the SparkConfig + SparkError + spark::init surface contract, plus
  [`docs/product/architecture/adr-0015-spark-single-init-invariant.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0015-spark-single-init-invariant.md)
  for the global-init semantics relevant to S09 / S10.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-11 UTC at HEAD.
- Kaleidoscope SHA: `0dd0988db154f6e158ec04502789bb730135b103`
- Method: driven by the **spark-consumer** fixture under
  `harness/spark-consumer/`. The fixture is a standalone Rust
  binary that links `spark` by path against the kaleidoscope HEAD
  snapshot, exposes `--scenario <name>` flags, and prints a
  single structured outcome line (`scenario=... result=ok|fail
  detail=...`). The runner builds the fixture image via
  `docker compose --profile fixture build spark-consumer`, then
  runs the scenario `s01-init-and-emit-trace` and asserts the outcome line.
  S01 additionally runs on the compose network so the SDK's OTLP
  exporter reaches aperture; the runner asserts a matching
  `event=sink_accepted signal=traces resource.service.name=...`
  line in aperture's container stderr and that the otelcol-sink
  file-exporter capture contains the round-tripped span.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/spark-consumer-build.txt`](evidence/spark-consumer-build.txt) — fixture image build log.
- [`evidence/consumer.stdout.txt`](evidence/consumer.stdout.txt) — verbatim structured outcome line.
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner trace.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's container stderr; the matched sink_accepted line is the contract.
- [`evidence/otlp-received.jsonl`](evidence/otlp-received.jsonl) — otelcol-sink's file-exporter capture (independent evidence of the round-trip reaching the downstream).

## Issues

None.

## Notes

This expectation was unblocked by the spark-consumer fixture
landing on 2026-05-11. Future S-prefix expectations follow the
same pattern: add a scenario branch to
`harness/spark-consumer/src/main.rs`, write a thin runner.sh
that invokes it, run `run-expectation.sh`.
