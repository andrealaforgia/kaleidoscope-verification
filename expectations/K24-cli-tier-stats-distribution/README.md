# K24 — cli-tier-stats-distribution

## Surface

`kaleidoscope-cli` operator binary (`place`, `stats`).

## Behaviour

`stats <tenant> <data-dir>` reports per-tier Cinder placement counts as
`hot=H` / `warm=W` / `cold=C` (in that fixed order, only non-zero tiers
emitted). A known 2-hot / 1-warm / 1-cold placement mix produces
`hot=2`, `warm=1`, `cold=1`.

Covers **UC-TIER-017** (tier distribution reflected in stats). Extends K09
(which pinned only the `hot=` line) to the full distribution.

## Source

- External contract anchor: `kaleidoscope-cli` `run_stats` Cinder tier
  accounting (usage header: per-tier non-zero lines).
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-017.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place a 2/1/1 hot/warm/cold mix via `place`, run `stats acme`,
  assert `hot=2`, `warm=1`, `cold=1`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/stats.out`](evidence/stats.out).

## Issues

None.

## Notes

`.no-compose` marker. Uses `place` directly (no `ingest`), so the Lumen
side is empty (`records=0`) and the asserted lines are pure Cinder tier
counts.
