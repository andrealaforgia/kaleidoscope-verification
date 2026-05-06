# A02 — otlp-grpc-logs-accepted

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

Given aperture is running with both listeners bound (gRPC `:4317`,
HTTP `:4318`) and a sink configured
When an OTLP/grpc client sends an `ExportlogServiceRequest` containing N logs to the matching listener
Then aperture acks the request
And aperture's stderr emits an `event=sink_accepted signal=logs` line
naming the resource's `service.name` and reporting `record_count=N`.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A2**.
- External contract anchor: [docs/feature/aperture/slices/slice-01-walking-skeleton.md:42](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/feature/aperture/slices/slice-01-walking-skeleton.md).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:28:24Z
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: dockerised harness; aperture built from the HEAD snapshot, invoked with `--config /etc/aperture/aperture.toml` (`kind = "forwarding"`, downstream `http://otelcol-sink:4318`). One logs payload from the upstream `telemetrygen` image (`ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0`) tagged `service.name="expectation-A02-pilot"` is sent to aperture's grpc listener. The shared driver `harness/assert-signal-acceptance.sh` verifies that telemetrygen exits 0 (proves the ack) and that aperture's container stderr contains exactly one `event=sink_accepted` line for this signal and service with a positive `record_count`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning record (SHA, dirty, host, timestamp).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner log: aperture ready, telemetrygen exit 0, sink_accepted matched.
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt) — the client's own log.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's container stderr captured live during the run; the matched line is verbatim:
  `aperture-1  | {"timestamp":"2026-05-06T23:28:24.950802Z","level":"INFO","event":"sink_accepted","sink":"forwarding","downstream":"http://otelcol-sink:4318","signal":"logs","record_count":1,"downstream_latency_ms":1,"resource.service.name":"expectation-A02-pilot"}`
- [`evidence/otlp-received.jsonl`](evidence/otlp-received.jsonl) — the otelcol-sink's file-exporter capture, independent third-party evidence that the payload reached the downstream carrying the expected `service.name`.

## Issues

None directly. Issue 001 (now closed) made this expectation testable.

## Notes

None.
