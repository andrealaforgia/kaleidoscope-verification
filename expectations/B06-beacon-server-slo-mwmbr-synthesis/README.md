# B06 — beacon-server-slo-mwmbr-synthesis

## Surface

Beacon (alerting engine). SLO multi-window multi-burn-rate synthesis.
Operator-facing in intent.

## Behaviour (intended)

An SLO declaration (objective + window) synthesises a set of Multi-Window
Multi-Burn-Rate alert rules per Google SRE conventions. The synthesised
rules tick on their own schedules and emit incidents through the same
sink path as hand-authored rules.

## Status: `pending` — NOT black-box reachable (SLO engine is unwired)

The Beacon harness exists now (B01/B02/B04/B05 prove it), so the old
blocker is gone. B06 stays unverifiable for a different, specific reason:
the SLO engine is library-and-tests only and is not wired into the
operator surface. At `dc826da`:

- `crates/beacon/src/slo.rs` exposes `pub fn synthesise_slo(slo: &Slo) ->
  Vec<Rule>`, and it is correct and exhaustively tested
  (`crates/beacon/tests/slice_05_slo_burn_rate.rs`, byte-equal firing
  patterns).
- But `synthesise_slo` is called by NOTHING except those tests. The rule
  loader (`crates/beacon/src/loader.rs`) does not parse SLO declarations,
  and `beacon-server` (`crates/beacon-server/src/`) never references
  `slo`/`Slo`/`synthesise_slo`. There is no `--slo` flag and no SLO file
  type.

So an operator cannot configure an SLO through beacon-server and get
synthesised MWMBR rules ticking. There is no externally observable
surface to drive, hence no black-box expectation. This is the
assessment's known "unreachable SLO engine" finding, acknowledged by the
implementer (message 021).

## Verification

- Status: `pending` (not black-box reachable at `dc826da`; SLO synthesis
  is library + in-suite tests only, not wired into beacon-server or the
  rule loader).
- The synthesis correctness is credited to the in-suite test
  `crates/beacon/tests/slice_05_slo_burn_rate.rs` (byte-equal MWMBR
  firing patterns), not claimed black-box here.
- Becomes buildable on the same Beacon harness the moment an SLO loading
  path is wired into beacon-server (an SLO file type or `--slo` flag that
  feeds `synthesise_slo` into the live catalogue).

## Evidence

None black-box (no operator surface to exercise).

## Source

- `crates/beacon/src/slo.rs:106` (`synthesise_slo`), `slice-05-slo-burn-rate.md`.
- Unreachability: no caller outside `crates/beacon/tests/slice_05_slo_burn_rate.rs`;
  `loader.rs` has no SLO parse; `beacon-server/src/` has no SLO reference.

## Notes

Distinct from the other B-series: B01/B02/B04/B05 are satisfied and B03 is
a `broken` doc-vs-behaviour finding (issue 010); B06 is a reachability
gap, not a behaviour defect — the code is right and tested, it is simply
not exposed to operators yet. Recorded honestly rather than faked or left
looking merely harness-blocked.
