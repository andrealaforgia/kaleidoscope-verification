# A03 — otlp-grpc-metrics-accepted

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

Given aperture is running with both listeners bound (gRPC `:4317`,
HTTP `:4318`) and a sink configured
When an OTLP/grpc client sends an `ExportmetricServiceRequest` containing N metrics to the matching listener
Then aperture acks the request
And aperture's stderr emits an `event=sink_accepted signal=metrics` line
naming the resource's `service.name` and reporting `data_point_count=N`.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A3**.
- External contract anchor: [docs/feature/aperture/slices/slice-04-metrics.md:42](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/feature/aperture/slices/slice-04-metrics.md).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-27 UTC at HEAD (`cf0ac15`). Cycle 28
  cold retry GREEN at first attempt ("data_point_count=1 for
  service expectation-A03-pilot"). Cycle-27 double-fail
  confirmed flake, same disposition as closed issues 006/007.
- Earlier satisfaction: 2026-05-06T23:28:28Z at `6b09c0d` and
  across many later cycles.
- Method: dockerised harness; aperture built from the HEAD snapshot, invoked with `--config /etc/aperture/aperture.toml` (`kind = "forwarding"`, downstream `http://otelcol-sink:4318`). One metrics payload from the upstream `telemetrygen` image (`ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0`) tagged `service.name="expectation-A03-pilot"` is sent to aperture's grpc listener. The shared driver `harness/assert-signal-acceptance.sh` verifies that telemetrygen exits 0 (proves the ack) and that aperture's container stderr contains exactly one `event=sink_accepted` line for this signal and service with a positive `data_point_count`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning record (SHA, dirty, host, timestamp).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner log: aperture ready, telemetrygen exit 0, sink_accepted matched.
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt) — the client's own log.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's container stderr captured live during the run; the matched line is verbatim:
  `aperture-1  | {"timestamp":"2026-05-06T23:28:28.320805Z","level":"INFO","event":"sink_accepted","sink":"forwarding","downstream":"http://otelcol-sink:4318","signal":"metrics","data_point_count":1,"downstream_latency_ms":0,"resource.service.name":"expectation-A03-pilot"}`
- [`evidence/otlp-received.jsonl`](evidence/otlp-received.jsonl) — the otelcol-sink's file-exporter capture, independent third-party evidence that the payload reached the downstream carrying the expected `service.name`.

## Issues

None directly. Issue 001 (now closed) made this expectation testable.

## Notes

None.
