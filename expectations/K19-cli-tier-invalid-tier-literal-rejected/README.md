# K19 — cli-tier-invalid-tier-literal-rejected

## Surface

`kaleidoscope-cli` operator binary (`place`, tier literal parsing).

## Behaviour

Tier literals are case-sensitive lowercase `hot`/`warm`/`cold`. Upper-case
(`HOT`) or unknown (`archive`) values are rejected non-zero with
`invalid tier "<value>": expected one of hot, warm, cold`.

Covers **UC-TIER-010** (invalid tier literal rejected, case-sensitive).

## Source

- External contract anchor: `kaleidoscope-cli` tier-literal parse;
  usage header (`<tier> MUST be the literal lowercase string`).
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-010.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: `place item-1 HOT` and `place item-1 archive`; assert both exit
  non-zero with the exact invalid-tier diagnostic.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/place-HOT.out`](evidence/place-HOT.out), [`evidence/place-archive.out`](evidence/place-archive.out) and their `.rc` siblings.

## Issues

None.

## Notes

`.no-compose` marker. The same tier-literal guard applies to `migrate`'s
`<to_tier>`; `place` is the representative surface here.
