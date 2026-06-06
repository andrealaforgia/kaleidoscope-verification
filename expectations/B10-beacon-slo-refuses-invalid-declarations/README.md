# B10 — beacon-slo-refuses-invalid-declarations

## Surface

Beacon (`beacon-server`), the `[[slo]]` operator-path honesty guardrails
(ADR-0067 F2/F3, `beacon-slo-operator-path-v0`). Operator-facing.
Complements [B06](../B06-beacon-server-slo-mwmbr-synthesis/README.md) (the
happy path). Reuses the Beacon harness.

## Behaviour

Given a rules dir holding only an INVALID `[[slo]]` declaration
When beacon-server loads it
Then it REFUSES the declaration at load with the exact diagnostic, NO rule
is synthesised (no degenerate always-fire footgun reaches the catalogue),
and with no valid rule left beacon refuses to start (exit 1). Three cases:

1. `target_availability = 1.0` (or ≤0 / ≥1) → `invalid target_availability
   1 (must be strictly greater than 0 and strictly less than 1) in SLO
   "<svc>"`.
2. `error_budget_period = "7d"` → `unsupported error_budget_period "7d"
   (only "30d" is supported at v0) in SLO "<svc>"`.
3. Two `[[slo]]` for the same service → colliding synthesised names → the
   duplicate REFUSES and DROPS the colliding rules (never a silent
   shadow); the diagnostic names the duplicate rule.

## Why this matters

`synthesise_slo` is correct, but a careless SLO is a footgun: `target=1.0`
gives a zero error budget (always firing), an unsupported period silently
under/over-alerts, and a name collision would silently shadow a rule. The
guardrails refuse-loud-at-the-door instead, with messages an operator can
act on. The "no rule synthesised" half is load-bearing: a refused
declaration must not leave a degenerate rule ticking.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`905abaa`). GREEN: each of the
  three invalid declarations produced its exact `rule load diagnostic` and
  `no rules loaded; refusing to start` (exit 1), with no
  `beacon-server starting rules_loaded>=1` and no `beacon.reload.succeeded`.
- Method: self-contained (`.no-compose`). Builds beacon-server from the
  HEAD snapshot, runs it three times — one per invalid `[[slo]]` fixture
  (`rules-badtarget`, `rules-badperiod`, `rules-dup`) — with a dead
  `--backend` (refusal is at LOAD, before any poll, so no mock and no 30s
  tick wait). Asserts the diagnostic, the exact message substring, the
  refuse-to-start exit, and the absence of any started/reloaded rule.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `905abaa`.
- [`evidence/badtarget.stderr.txt`](evidence/badtarget.stderr.txt),
  [`evidence/badperiod.stderr.txt`](evidence/badperiod.stderr.txt),
  [`evidence/dup.stderr.txt`](evidence/dup.stderr.txt) — the exact
  diagnostics + refuse-to-start.
- [`evidence/observation.txt`](evidence/observation.txt) — exit codes.
- `rules-badtarget/`, `rules-badperiod/`, `rules-dup/` — the fixtures.

## Source

- `crates/beacon/src/loader.rs` (`RawSlo::into_slo` validation: the exact
  `invalid target_availability` / `unsupported error_budget_period`
  messages; `detect_duplicate_names`: refuse + drop the colliding rules,
  never silently shadow, ADR-0067 F2), `crates/beacon-server/src/main.rs`
  (per-diagnostic `rule load diagnostic`; `no rules loaded; refusing to
  start` exit 1). feat `41e7844`/`4bc8d58`.

## Notes

The implementer enumerated these exact contracts (message 026) and asked
for them under contract; they are the SLO honesty guardrails. The fourth
case she named — a malformed `[[slo]]` edit + SIGHUP keeps the PREVIOUS
catalogue (ADR-0063 all-or-nothing) — is the same shape as
[B08](../B08-beacon-sighup-refuses-malformed-keeps-previous/README.md) and
not separately pinned here.
