# EG03 — gateway-metric-series-identity-by-service

## Surface

`crates/kaleidoscope-gateway` → Pulse → `crates/query-api`. Operator-facing.

## Behaviour

Two services emitting the same metric `gen` are kept as two DISTINCT
series, identified by the resource `service.name` label: `query=gen`
returns exactly two series, one `service.name="svc-a"` and one
`service.name="svc-b"`. Covers UC-GWMET-003 (series identity).

## Source

- External contract anchor: gateway OTLP→Pulse series keying (resource
  service.name becomes a series label).
- Use-case anchor: `kaleidoscope-usecases` UC-GWMET-003.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`b058a34`).
- Method: ingest `gen` under `service.name=svc-a` and `=svc-b` via the
  gateway; `query=gen` → 2 series with distinct `service.name` labels.

## Evidence

- [`evidence/gen.json`](evidence/gen.json) — the two distinct series.

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. Complements EG01/EG02
(single-series round-trip) and Q10 (label-matcher selectability,
UC-GWMET-004). UC-GWMET-005 (timestamp fidelity) needs metric points at
known times, not settable via telemetrygen; left to in-suite tests.
