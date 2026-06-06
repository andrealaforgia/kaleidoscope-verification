# K15 — cli-tier-migrate-updates-persisted

## Surface

`kaleidoscope-cli` operator binary (`place`, `migrate`, `get-tier`).

## Behaviour

After `place acme /data item-1 hot`, a `migrate acme /data item-1 warm`
writes exactly `migrated tenant=acme item=item-1 from=hot to=warm`, and a
fresh `get-tier` reads back `tier=warm`. The migration is persisted, not
just reported.

Covers **UC-TIER-003** (migrate an item between tiers) and **UC-TIER-004**
(migrate updates the persisted tier).

## Source

- External contract anchor: `kaleidoscope-cli` `run_migrate`.
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-003/004.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place hot, migrate to warm, assert the from/to line, then
  assert a fresh `get-tier` reports `tier=warm`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/migrate.out`](evidence/migrate.out), [`evidence/gettier.out`](evidence/gettier.out).

## Issues

None.

## Notes

`.no-compose` marker.
