# K23 — cli-tier-tenant-isolation

## Surface

`kaleidoscope-cli` operator binary (`place`, `list-items`, `get-tier`).

## Behaviour

Tier state is per-tenant. The same item id placed in different tiers
under two tenants does not bleed across the tenant boundary: `item-x` is
`hot` under `acme` and `cold` under `globex`; each tenant's `list-items`
and `get-tier` see only their own placement.

Covers **UC-TIER-018** (tenant isolation of tier state).

## Source

- External contract anchor: Cinder per-tenant tier keying behind the
  `kaleidoscope-cli` tiering subcommands.
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-018.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place acme/item-x hot and globex/item-x cold; assert each
  tenant's list-items/get-tier reflect only their own tier with no bleed.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/isolation.out`](evidence/isolation.out).

## Issues

None.

## Notes

`.no-compose` marker. Complements LQ07 (read-path tenant isolation for
logs) on the Cinder tier-state surface.
