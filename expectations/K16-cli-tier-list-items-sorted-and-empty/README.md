# K16 — cli-tier-list-items-sorted-and-empty

## Surface

`kaleidoscope-cli` operator binary (`place`, `list-items`).

## Behaviour

`list-items <tenant> <data-dir> <tier>` prints every ItemId placed under
the tenant in that tier, one per line, lexicographically sorted
regardless of placement order. A tier with no items prints nothing and
still exits 0.

Covers **UC-TIER-005** (list items in a tier, lex-sorted) and
**UC-TIER-006** (list an empty tier: empty stdout, exit 0).

## Source

- External contract anchor: `kaleidoscope-cli` `run_list_items`.
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-005/006.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: place item-b/item-a/item-c hot (out of order), assert
  `list-items hot` equals the lex-sorted set, assert `list-items cold`
  is empty with exit 0.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/list-hot.out`](evidence/list-hot.out), [`evidence/list-cold.out`](evidence/list-cold.out), [`evidence/list-cold.rc`](evidence/list-cold.rc).

## Issues

None.

## Notes

`.no-compose` marker.
