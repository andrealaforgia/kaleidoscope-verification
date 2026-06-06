# K18 — cli-tier-unknown-item-clean-message

## Surface

`kaleidoscope-cli` operator binary (`migrate`, `get-tier`)
unknown-item path. Operator-facing diagnostic.

## Behaviour (desired contract)

`migrate`/`get-tier` against an item that was never placed fail closed
(exit 1) AND name the offending item cleanly as `unknown item "ghost"`,
per **UC-TIER-008** and **UC-TIER-009** and the CLI's own help text
(`cannot migrate unknown item "<item_id>" for tenant <tenant>`).

## Source

- External contract anchor: `kaleidoscope-cli` `run_migrate` /
  `run_get_tier` error path; CLI usage header wording.
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-008/009.

## Verification

- Status: `broken` — grounds [issue 011](../../issues/011-cli-unknown-item-diagnostic-leaks-itemid-debug.md).
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: `migrate acme /data ghost warm` and `get-tier acme /data ghost`;
  assert exit 1 (holds) AND stderr contains `unknown item "ghost"` (fails).

## Observed vs desired

Fail-closed already holds: both paths exit 1. The message assertion is
RED because the binary leaks the internal newtype Debug form:

```
kaleidoscope-cli: cinder migrate: cannot migrate unknown item ItemId("ghost") for tenant acme
```

`ItemId("ghost")` should read `"ghost"`. This is a transition-proof
expectation: it asserts the documented contract and flips GREEN unchanged
once the `ItemId(...)` wrapper is dropped from the diagnostic.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/migrate-ghost.out`](evidence/migrate-ghost.out), [`evidence/migrate-ghost.rc`](evidence/migrate-ghost.rc), [`evidence/gettier-ghost.out`](evidence/gettier-ghost.out), [`evidence/gettier-ghost.rc`](evidence/gettier-ghost.rc).

## Issues

- [011](../../issues/011-cli-unknown-item-diagnostic-leaks-itemid-debug.md) — unknown-item diagnostic leaks `ItemId(...)` Debug form.

## Notes

`.no-compose` marker. Low severity (cosmetic / contract fidelity); the
fail-closed safety property is already met.
