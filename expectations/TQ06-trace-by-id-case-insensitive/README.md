# TQ06 — trace-by-id-case-insensitive

## Surface

`crates/trace-query-api` binary (`/api/v1/traces/by_id`), via the
gateway → Ray → trace-query-api round-trip.

## Behaviour

The `/by_id` arm matches a `trace_id` case-insensitively: an UPPERCASE
32-hex id resolves the same trace stored under its canonical lowercase id,
returning the same spans. Covers UC-TRC-005.

## Source

- External contract anchor: trace-query-api by-id lookup (case-insensitive
  hex match), ADR-0053.
- Use-case anchor: `kaleidoscope-usecases` UC-TRC-005.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`6a54ae1`).
- Method: ingest 5 traces for `tq06-pilot`; discover the canonical
  lowercase `trace_id` from the window arm; query `/by_id` with its
  uppercase form → 200 and the same span set as the lowercase lookup
  (2 spans both ways).

## Evidence

- [`evidence/window.json`](evidence/window.json) — canonical id discovery.
- [`evidence/byid-lower.json`](evidence/byid-lower.json), [`evidence/byid-upper.json`](evidence/byid-upper.json) — equal span sets.

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. Completes UC-TRC (8/8) with
TQ01-TQ05. Complements TQ01 (malformed id → 400) and TQ02 (by-id
round-trip).
