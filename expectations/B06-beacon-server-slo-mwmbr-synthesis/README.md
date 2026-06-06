# B06 — beacon-server-slo-mwmbr-synthesis

## Surface

Beacon (`beacon-server`), SLO multi-window multi-burn-rate synthesis via
the `[[slo]]` operator path (ADR-0067, `beacon-slo-operator-path-v0`).
Operator-facing. Reuses the B02 Beacon harness.

## Behaviour

Given a rules dir holding one `[[slo]]` declaration (service, good/total
event queries, target availability, a webhook sink) and a backend that
reports the burn condition Active
When beacon-server loads it and evaluates the synthesised rules
Then the loader validates the SLO and expands it into FOUR Multi-Window
Multi-Burn-Rate rules — `<service>_slo_page_1h_5m`, `_page_6h_30m`,
`_ticket_1d_2h`, `_ticket_3d_6h` — which tick and emit Firing incidents to
the SLO's sinks, each labelled `slo_service=<service>` and
`slo_window=<long>/<short>`. One declaration, four firing rules.

## History — was the "unreachable SLO engine", now reachable

`synthesise_slo` was correct and exhaustively in-suite tested
(`crates/beacon/tests/slice_05_slo_burn_rate.rs`) but had NO caller
outside those tests: the loader did not parse SLOs and beacon-server never
referenced it. So B06 was documented `pending` — not black-box reachable
(the four-quadrants assessment's "unreachable SLO engine"), credited to the
in-suite test. The verifier flagged exactly this gap; the implementer then
wired the operator path (`beacon-slo-operator-path-v0`, ADR-0067, feat
`4bc8d58`): `[[slo]]` is validated (`RawSlo::into_slo`) and expanded via
`synthesise_slo` VERBATIM in the loader, on both startup and SIGHUP reload.
B06 is now grounded end to end.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`905abaa`, re-verified after the SHA reconciliation below). GREEN:
  `rules_loaded=4` from one `[[slo]]`; all four synthesised rules fired to
  the webhook (`b06svc_slo_page_1h_5m`, `_page_6h_30m`, `_ticket_1d_2h`,
  `_ticket_3d_6h`), each `labels.slo_service=b06svc`.
- Method: self-contained (`.no-compose`). beacon-server + the always-Active
  mock (backend + webhook catcher) on a throwaway docker network; the rules
  dir holds one `[[slo]]`. The synthesised rules have a fixed
  `interval=30s` (the MWMBR construction; ADR-0067), and beacon promotes
  Pending→Firing on a subsequent tick, so the runner waits ~38s for the
  first firings. Asserts a Firing incident from a synthesised rule (name +
  `slo_service` label) and ≥2 distinct synthesised rules (the fan-out).

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `905abaa`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — the four
  synthesised-rule incidents.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — `rules_loaded=4` from one `[[slo]]`.
- [`rules/slo.toml`](rules/slo.toml), [`mock/server.py`](mock/server.py).

## Source

- `crates/beacon/src/loader.rs:241-243` (`[[slo]]` → `RawSlo::into_slo` →
  `synthesise_slo` → extend rules), `crates/beacon/src/slo.rs`
  (`synthesise_slo`, the four-row `MWMBR_TABLE`, `synthesise_row` naming +
  `slo_service`/`slo_window` labels, `for_duration=0` / `interval=30s`).
  ADR-0067, feat `4bc8d58` (origin/main; `41e7844` was a transient pre-push local HEAD that was amended — message 026).

## Notes

Completes the Beacon happy path; with B10 (the refusals) the SLO operator path is fully pinned. The SLO PromQL
correctness (the burn-rate expressions) stays credited to the in-suite
`slice_05_slo_burn_rate.rs` byte-equal test — the mock fires every rule
regardless of the query, so B06 proves the OPERATOR PATH (declare → load →
synthesise → tick → emit), not the PromQL maths. The loader's
refuse-on-collision and SLO-validation (ADR-0067 F3) are the natural B10
follow-ons if pinned.
