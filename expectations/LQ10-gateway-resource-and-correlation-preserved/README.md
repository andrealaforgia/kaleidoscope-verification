# LQ10 — gateway-resource-and-correlation-preserved

## Surface

`crates/kaleidoscope-gateway` → Lumen → `crates/log-query-api`
(`/api/v1/logs`). Operator-facing round-trip.

## Behaviour

A log exported through the gateway preserves its OTLP resource attributes
and its trace/span correlation IDs all the way into Lumen, readable via
log-query-api:
- `resource_attributes."service.name"` survives (UC-GWLOG-003);
- `trace_id` (16 bytes) and `span_id` (8 bytes) survive byte-for-byte,
  enabling trace↔log join (UC-GWLOG-005).

## Source

- External contract anchor: gateway OTLP→Lumen mapping (resource
  attributes + correlation fields).
- Use-case anchor: `kaleidoscope-usecases` UC-GWLOG-003/005.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`b058a34`).
- Method: ingest a log via the gateway with `service.name=lq10-svc`,
  `trace_id=deadbeef…` (16B) and `span_id=cafef00d…` (8B); query
  log-query-api → the record carries the same service.name and the same
  trace_id/span_id bytes (compared as hex).

## Evidence

- [`evidence/logs.json`](evidence/logs.json) — the round-tripped record.

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. Severity mapping
(UC-GWLOG-004) is LQ05/LQ09; batch-many-persist (UC-GWLOG-006) is shown by
LQ04's multi-record fixture; partial-success (UC-GWLOG-007) is 🟡 and
HTTP/protobuf (UC-GWLOG-009) 🔭.
