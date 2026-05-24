# EG01 — gateway-otlp-metric-readable-via-query-api

## Surface

`kaleidoscope-gateway` (write side, OTLP/HTTP :4318) plus
`query-api` (read side, :9090) sharing a Pulse store on the same
filesystem volume. Operator-facing on both halves.

## Behaviour

An OTLP/HTTP/protobuf metric submitted to the gateway lands in
the Pulse store, survives a gateway restart, and is readable by
query-api as a Prometheus `matrix` response with the correct
`__name__` label. This is the integration thesis from the
kaleidoscope README ("the platform now runs end to end") under
contract for the first time.

## Source

- External contract anchor: ADR-0041 (aperture-storage-sink
  translation + tenancy) plus ADR-0042 (query-api contract,
  matrix shape). The contract is the conjunction of the two:
  whatever the storage sink writes, query-api must read back
  as a Prometheus matrix.
- Code: `crates/aperture-storage-sink/`, `crates/pulse/`,
  `crates/query-api/`, plus the binary composition roots in
  `crates/kaleidoscope-gateway/src/main.rs` and
  `crates/query-api/src/main.rs`.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-24 UTC at HEAD (`0c1d66b`).
- Method: `harness/run-eg.sh` builds both images from the
  snapshot, then a sequential scenario:
  1. Start gateway with shared /data + DEFAULT_TENANT=acme;
     wait for aperture's `event=ready` on stderr.
  2. Send one OTLP/HTTP/protobuf metric (telemetrygen default:
     `gen`, type Gauge, service.name=eg01-pilot). telemetrygen
     only emits well-formed wire bytes, so this validates the
     forwarding-and-persistence correctness, not the protobuf
     parser.
  3. SIGTERM gateway so Pulse flushes.
  4. Start query-api on the same /data with QUERY_TENANT=acme.
  5. GET `/api/v1/query_range?query=gen&start=...&end=...&step=15s`.
  6. Assert response `status=success`, non-empty `data.result`,
     `data.result[0].metric.__name__ == "gen"`.

The metric name is the telemetrygen default `gen` rather than
a domain-named one because query-api v0 (ADR-0042) restricts
the PromQL surface to bare metric names matching Prometheus's
`[a-zA-Z_:][a-zA-Z0-9_:]*` production. OTLP semantic-convention
names with dots (e.g. `lumen.ingest.count`) currently fail
parser; that's a v1 PromQL gap, not an EG01 contract issue.

## Evidence

- `evidence/EG01.stdout.txt` — runner trace.
- `evidence/EG01.gateway.build.txt`, `EG01.query-api.build.txt`
  — image build logs.
- `evidence/telemetrygen.stderr.txt` — wire-side trace.
- `evidence/gateway.stderr.txt` — gateway container stderr.
- `evidence/query-api.stderr.txt` — query-api container stderr.
- `evidence/query-response.json` — the raw HTTP response.

## Issues

None yet.

## Notes

`.no-compose` marker — the EG harness manages container
lifecycle directly rather than through docker-compose because
the scenario sequences gateway-up → ingest → gateway-down →
query-up, which is awkward to express in a single compose file.

This is the catalogue's first true end-to-end through the
durable pipeline. Failure modes the catalogue does NOT yet
exercise (will follow as EG02-EG05):
- OTLP/gRPC ingest path (vs OTLP/HTTP/protobuf here).
- Log signal via log-query-api `/api/v1/logs` (when its
  Dockerfile ships).
- Trace signal via trace-query-api (designed only, ADR-0048).
- Restart durability mid-write (kill-9 before flush — see
  [N18](../../known-gaps.md)).
- Multi-tenant isolation (one tenant's writes invisible to
  another's reads).
