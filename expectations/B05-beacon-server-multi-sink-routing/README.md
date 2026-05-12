# B05 — beacon-server-multi-sink-routing

## Surface

Beacon (alerting engine over any OTel-compatible PromQL backend).
Operator-facing.

## Behaviour

A rule with N configured sinks (webhook, SMTP, Mattermost, Zulip, Grafana OnCall) emits each incident to ALL configured sinks. Failed deliveries are classified Transient (5xx, retried) or Permanent (4xx, surfaced as stderr diagnostic) per ADR-0035.

## Source

- External contract anchor:
  [`docs/feature/beacon-v0/slices/slice-04-sink-routing.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/feature/beacon-v0/slices/slice-04-sink-routing.md)
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
