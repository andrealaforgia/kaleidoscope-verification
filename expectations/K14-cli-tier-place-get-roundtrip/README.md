# K14 — cli-tier-place-get-roundtrip

## Surface

`kaleidoscope-cli` operator binary (`place`, `get-tier`). Operator-facing.

## Behaviour

`place <tenant> <data-dir> <item> <tier>` writes one line
`placed tenant=<t> item=<i> tier=<tier>` and persists the placement.
A subsequent `get-tier <tenant> <data-dir> <item>`, run in a fresh
process against the same data dir, reads it back as `tier=<tier>`.

Covers **UC-TIER-001** (place an item in a tier) and **UC-TIER-002**
(get an item's tier). Because `get-tier` runs in a separate container
against the same volume, a pass also demonstrates **UC-TIER-016**
(placement survives a fresh process reading the same data dir).

## Source

- External contract anchor: `kaleidoscope-cli` `run_place` / `run_get_tier`
  (Cinder v1 tiering), documented in the binary's own usage header.
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-001/002/016.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: `place acme /data item-1 hot`, assert the placement line,
  then `get-tier` in a fresh container asserts `tier=hot`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/place.out`](evidence/place.out), [`evidence/gettier.out`](evidence/gettier.out).

## Issues

None.

## Notes

`.no-compose` marker (CLI driver builds the shipped Dockerfile from the
HEAD snapshot; no aperture stack needed).
