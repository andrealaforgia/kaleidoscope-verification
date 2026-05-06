# A08 — http-rejects-malformed-bytes

## Surface

Aperture (OTLP ingest gateway). Operator/integrator-facing.

## Behaviour

Given aperture is running with both listeners bound
When a client `POST`s a body that is not a valid OTLP/protobuf
`ExportTraceServiceRequest` to `:4318/v1/traces` with
`Content-Type: application/x-protobuf`
Then aperture responds HTTP `400`
And the response body cites a recognisable `OtlpViolation` Rule
discriminator (e.g. `WireType::ProtobufDecode`,
`WireType::EmptyInput`, `WireType::SignalMismatch`).

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A8**.
- External contract anchor:
  [`docs/feature/aperture/slices/slice-03-traces.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/feature/aperture/slices/slice-03-traces.md)
  line 44 ("`POST /v1/traces` with logs bytes -> HTTP 400, body
  contains `rule=...`, ...").

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:32 UTC
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: dockerised harness; aperture built from the HEAD snapshot.
  The runner posts 32 garbage bytes (`$'\xff\x00\xff\x01\x02\x03this-is-not-protobuf-bytes\xfe'`)
  to `http://localhost:4318/v1/traces` with
  `Content-Type: application/x-protobuf`, captures the response
  code and body, and asserts code 400 plus the presence of an
  `OtlpViolation` Rule token in the body.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning record.
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner log.
- [`evidence/response.code.txt`](evidence/response.code.txt) — the literal HTTP status code observed: `400`.
- [`evidence/response.body.txt`](evidence/response.body.txt) — the response body byte-for-byte. Verbatim:
  `otlp violation: rule=WireType::ProtobufDecode signal=Traces framing=HttpProtobuf locus=byte 1 expected="valid protobuf wire bytes per opentelemetry-proto descriptor" observed="invalid varint"`
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's container stderr captured during the run.

## Issues

None.

## Notes

The body cites `WireType::ProtobufDecode` and the precise locus
(byte 1) where the decode failed, plus the expected vs observed
descriptions. This is more diagnostic than the catalogue's minimum
contract (just a Rule discriminator) and is captured verbatim as
positive evidence of the harness's `OtlpViolation::Display`
implementation.
