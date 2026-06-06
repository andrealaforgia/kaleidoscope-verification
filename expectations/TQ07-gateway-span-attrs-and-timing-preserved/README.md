# TQ07 — gateway-span-attrs-and-timing-preserved

## Surface

`crates/kaleidoscope-gateway` → Ray → `crates/trace-query-api`
(`/api/v1/traces`). Operator-facing round-trip.

## Behaviour

A span exported through the gateway preserves its attributes and its
start/end timing into Ray, readable via trace-query-api:
- the span `name` survives;
- `start_time_unix_nano` and `end_time_unix_nano` survive with
  `end > start > 0` (duration preserved);
- span `attributes` survive (`peer.service=telemetrygen-client`,
  `net.peer.ip=1.2.3.4`).

Covers UC-GWTRC-005 (span attributes & timing preserved).

## Source

- External contract anchor: gateway OTLP→Ray span mapping (attributes +
  timing fields).
- Use-case anchor: `kaleidoscope-usecases` UC-GWTRC-005.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`b058a34`).
- Method: ingest 3 traces (parent+child) for `tq07-pilot` via the
  gateway; the window arm returns spans whose name, start/end timing, and
  attributes all survived.

## Evidence

- [`evidence/spans.json`](evidence/spans.json) — the round-tripped spans.

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. UC-GWTRC-004 (multi-span
parent+child) is shown by TQ02/TQ06 (by-id returns both spans);
UC-GWTRC-007 (one trace across two services) needs two services sharing a
trace id, not settable via telemetrygen — left to in-suite tests.
