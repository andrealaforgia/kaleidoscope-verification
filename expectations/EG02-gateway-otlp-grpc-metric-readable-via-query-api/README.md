# EG02 — gateway-otlp-grpc-metric-readable-via-query-api

## Surface

End-to-end via `kaleidoscope-gateway` over OTLP/gRPC (:4317) →
Pulse → `query-api`. Operator-facing. The gRPC counterpart to
[EG01](../EG01-gateway-otlp-metric-readable-via-query-api/README.md)
(OTLP/HTTP).

## Behaviour

Given the gateway is running and a metric is exported over OTLP/gRPC
When the gateway is stopped (Pulse flushes) and query-api reopens the same
`/data`
Then `query_range` returns the metric: `status=success`, a non-empty
matrix, `__name__=gen`.

## Why this matters

EG01 pins the HTTP ingest path. The gateway also serves an OTLP/gRPC
receiver (tonic) on :4317 — distinct code from the HTTP receiver. EG02
proves that path persists to Pulse and is read back identically, so an
operator exporting over gRPC gets the same durable, queryable result as
over HTTP. Together EG01/EG02 cover both OTLP transports end to end.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`3f7c657`). GREEN:
  `status=success`, 1 series, `__name__=gen`.
- Method: self-contained (`.no-compose`). `harness/run-eg.sh` builds the
  gateway + query-api from the HEAD snapshot. telemetrygen exports one
  counter `gen` over OTLP/gRPC (no `--otlp-http`) to the gateway's gRPC
  port mapped on a unique high host port (14335→4317); the gateway is
  SIGTERMed to flush Pulse; query-api reopens the same `/data` on 19102
  and `query_range` is asserted.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `3f7c657`.
- [`evidence/query-response.json`](evidence/query-response.json) — the
  matrix (`status=success`, `__name__=gen`).
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt),
  [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/query-api.stderr.txt`](evidence/query-api.stderr.txt).

## Source

- `crates/kaleidoscope-gateway` (OTLP/gRPC receiver on :4317, persists to
  Pulse), `crates/query-api` (reads Pulse). Same persistence + read path
  as EG01; only the ingest transport differs.

## Notes

Second E2E-via-gateway expectation. EG03+ (logs via log-query-api, traces
via trace-query-api, multi-tenant isolation) remain the natural next
batch. Uses host networking for telemetrygen (as EG01 does) and unique
high ports (N27).
