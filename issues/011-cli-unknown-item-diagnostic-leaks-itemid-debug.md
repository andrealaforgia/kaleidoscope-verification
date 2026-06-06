# 011 — CLI unknown-item diagnostic leaks the internal `ItemId(...)` Debug form

- Status: `open` (2026-06-06). Grounded RED by **K18** at kaleidoscope
  HEAD `545a2ba`.
- Severity: low (cosmetic / contract-fidelity; the command already fails
  closed with exit 1, but the operator-facing message exposes an internal
  Rust newtype representation instead of the documented item id).
- Surface: `kaleidoscope-cli` `migrate` and `get-tier` unknown-item path.
- Opened: 2026-06-06
- Source: observable-behaviour gap found while building the UC-TIER
  coverage batch (K14-K24) against `kaleidoscope-usecases`.

## The documented contract

`kaleidoscope-usecases/README.md` pins the unknown-item diagnostic:

- **UC-TIER-008** (migrate unknown item fails closed): "When `migrate
  acme /data ghost warm`, Then stderr `cannot migrate unknown item
  "ghost"`, exit 1".
- **UC-TIER-009** (get-tier unknown item fails closed): "error + exit 1
  (no silent default)".

The CLI's own help text repeats the clean form: `cannot migrate unknown
item "<item_id>" for tenant <tenant>`.

So the promised observable behaviour names the offending item as
`"ghost"` — the value the operator typed.

## Observed (black-box, K18)

At HEAD `545a2ba`, both `migrate acme /data ghost warm` and `get-tier
acme /data ghost` exit 1 (fail-closed — correct) but emit:

```
kaleidoscope-cli: cinder migrate: cannot migrate unknown item ItemId("ghost") for tenant acme
```

The message leaks the internal `ItemId(...)` newtype Debug wrapper around
the id instead of the documented bare `"ghost"`. An operator who typed
`ghost` sees `ItemId("ghost")`, which reads like an internal error rather
than "you named an item that does not exist".

## What would make K18 pass

The unknown-item diagnostic on both `migrate` and `get-tier` names the
item as `"ghost"` (the Display/quoted-string form), dropping the
`ItemId(...)` wrapper — exactly the wording UC-TIER-008/009 and the CLI
help already promise. Exit code stays 1. K18 asserts the desired contract
and will flip GREEN unchanged once the wrapper is gone.

## Scope note (verifier)

This is reported as a failing expectation about observable behaviour, not
a code-change instruction. The fix shape is the implementer's call.
