# K21 — cli-tier-evaluate-policy-cross-tenant

## Surface

`kaleidoscope-cli` operator binary (`place`, `evaluate-policy`, `get-tier`).

## Behaviour

`evaluate-policy` is the only tiering subcommand with no `<tenant_id>`
positional — it ages items across ALL tenants in one call. A hot item
placed under `acme` and another under `globex`, evaluated once with zero
thresholds, both advance (`evaluated migrated=2`; both now warm).

Covers **UC-TIER-013** (policy evaluation is cross-tenant).

## Source

- External contract anchor: `kaleidoscope-cli` `run_evaluate_policy`
  (cross-tenant by design; usage header).
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-013.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place acme/item-1 and globex/item-2 hot, single
  `evaluate-policy 0 0`, assert migrated=2 and both tenants' items warm.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/evaluate.out`](evidence/evaluate.out), [`evidence/tiers-after.out`](evidence/tiers-after.out).

## Issues

None.

## Notes

`.no-compose` marker.
