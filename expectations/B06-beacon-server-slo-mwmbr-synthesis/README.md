# B06 — beacon-server-slo-mwmbr-synthesis

## Surface

Beacon (alerting engine over any OTel-compatible PromQL backend).
Operator-facing.

## Behaviour

An SLO rule (objective + window) synthesises one or more Multi-Window Multi-Burn-Rate alert rules per Google SRE conventions. The synthesised rules tick on their own schedules and emit incidents through the same sink path as hand-authored rules.

## Source

- External contract anchor:
  [`docs/feature/beacon-v0/slices/slice-05-slo-burn-rate.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/feature/beacon-v0/slices/slice-05-slo-burn-rate.md)
  plus the ADRs referenced therein.

## Verification

- Status: `pending`
- Last verified: never (catalogue placeholder; see known-gaps.md N10).
- Method: TBD. Beacon v0 graduated at `f2c28b5`; `beacon-server`
  is now runnable (`beacon-server --rules <DIR> --backend <URL>`).
  External verification needs a harness similar to
  `harness/spark-consumer/` but for Beacon: a mock Prometheus
  HTTP backend (wiremock or a small adapter), a wiremock-based
  webhook sink fixture, plus docker-compose wiring so beacon-server
  can poll Prom and post incidents to the captured webhook. Not
  yet built.

## Evidence

None yet.

## Issues

None.

## Notes

This stub exists to make the Beacon surface visible in the
catalogue. Beacon's internal contracts are exercised by
`crates/beacon/tests/` and `crates/beacon-server/tests/`;
this expectation tracks the external (operator-facing)
contract that an EDD harness would assert.
