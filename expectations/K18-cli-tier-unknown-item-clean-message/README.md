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

- Status: `satisfied` — flipped GREEN 2026-06-06 at HEAD (`ddbe982`),
  resolving [issue 011](../../issues/011-cli-unknown-item-diagnostic-leaks-itemid-debug.md).
- Last verified: 2026-06-06 UTC at HEAD (`ddbe982`).
- Method: `migrate acme /data ghost warm` and `get-tier acme /data ghost`;
  exit 1 AND stderr now reads `cannot migrate unknown item "ghost" for
  tenant acme` (the clean documented form).

## Transition (RED → GREEN)

Grounded RED at `545a2ba`: fail-closed held (exit 1) but the diagnostic
leaked the internal newtype Debug form `ItemId("ghost")`. The implementer
fixed it in `cinder-unknown-item-diagnostic-v0` (deliver `ddbe982`):
`store.rs` now formats `{:?}` of `item.as_str()` (Debug of the `&str`),
so the message reads the documented `unknown item "ghost"`:

```
kaleidoscope-cli: cinder migrate: cannot migrate unknown item "ghost" for tenant acme
```

The transition-proof expectation flipped GREEN unchanged on the committed
fix — it always asserted the desired contract, never the leak.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/migrate-ghost.out`](evidence/migrate-ghost.out), [`evidence/migrate-ghost.rc`](evidence/migrate-ghost.rc), [`evidence/gettier-ghost.out`](evidence/gettier-ghost.out), [`evidence/gettier-ghost.rc`](evidence/gettier-ghost.rc).

## Issues

- [011](../../issues/011-cli-unknown-item-diagnostic-leaks-itemid-debug.md) — `resolved` (deliver `ddbe982`); the diagnostic now names the bare id.

## Notes

`.no-compose` marker. Low severity (cosmetic / contract fidelity); the
fail-closed safety property is already met.
