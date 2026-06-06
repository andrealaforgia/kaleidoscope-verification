# K20 — cli-tier-evaluate-policy-ages-items

## Surface

`kaleidoscope-cli` operator binary (`place`, `evaluate-policy`, `get-tier`).

## Behaviour

`evaluate-policy <data-dir> <hot_to_warm_secs> <warm_to_cold_secs>` ages
items one tier-step per pass. With zero thresholds, two freshly-placed
hot items move hot→warm on the first evaluation (`evaluated migrated=2`)
and warm→cold on the second. Aging is one step per pass, not a cascade.

Covers **UC-TIER-011** (hot→warm), **UC-TIER-012** (warm→cold) and
**UC-TIER-014** (zero thresholds well-defined: everything eligible moves).

## Source

- External contract anchor: `kaleidoscope-cli` `run_evaluate_policy`
  delegating to Cinder's age-based policy.
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-011/012/014.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place 2 hot, `evaluate-policy 0 0` → migrated=2 + both warm,
  second `evaluate-policy 0 0` → migrated=2 + both cold.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/evaluate-1.out`](evidence/evaluate-1.out), [`evidence/tiers-after-1.out`](evidence/tiers-after-1.out), [`evidence/evaluate-2.out`](evidence/evaluate-2.out), [`evidence/tiers-after-2.out`](evidence/tiers-after-2.out).

## Issues

None.

## Notes

`.no-compose` marker. The observed one-step-per-pass semantics (hot→warm
this pass, warm→cold next) is the well-defined behaviour UC-TIER-014 asks
for; it is asserted here, not assumed.
