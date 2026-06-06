# K17 — cli-tier-place-overwrite-idempotent

## Surface

`kaleidoscope-cli` operator binary (`place`, `get-tier`).

## Behaviour

`place` has overwrite semantics: re-placing an existing item updates its
tier (and migrated_at) without error. Place `item-1 hot` then
`item-1 cold`; the second place exits 0, reports
`placed tenant=acme item=item-1 tier=cold`, and `get-tier` reads `cold`.

Covers **UC-TIER-007** (re-place overwrites tier idempotently).

## Source

- External contract anchor: `kaleidoscope-cli` `run_place` (overwrite
  semantics, documented in the usage header).
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-007.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place hot, place same id cold (assert exit 0 + new line),
  assert `get-tier` reports `tier=cold`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/place2.out`](evidence/place2.out), [`evidence/place2.rc`](evidence/place2.rc), [`evidence/gettier.out`](evidence/gettier.out).

## Issues

None.

## Notes

`.no-compose` marker.
