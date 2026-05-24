# Q01 — query-api-fails-closed-no-tenant

## Surface

`query-api` operator binary (port 9090). Operator-facing.

## Behaviour

`query-api` started without `KALEIDOSCOPE_QUERY_TENANT`
(or with that variable set to the empty string) refuses to
bind its HTTP listener. It exits non-zero AND emits a
`tracing::error!(event = "health.startup.refused", reason = ...)`
event on stderr naming the tenant variable as the cause.
The Earned-Trust posture (wire → probe → use, ADR-0042 DD9) is
operator-observable: the binary refuses to come up half-open.

## Source

- External contract anchor:
  [`ADR-0042`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0042-query-api-contract-and-promql-subset.md)
  DD9 ("Earned-Trust probe: wire → probe → use; refuse a
  half-up listener").
- Code: `crates/query-api/src/composition.rs::probe` and
  `crates/query-api/src/main.rs` (the `Err(reason)` branch
  before `TcpListener::bind`).
- Unit-test anchor:
  `crates/query-api/src/composition.rs::tests::tenant_resolution_is_fail_closed_on_unset_or_empty`.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-23 UTC at HEAD (`0c1d66b`).
- Method: `harness/run-query-api.sh` builds the query-api
  runtime image from the snapshot's `Dockerfile.query-api`,
  then `docker run` with a writable /data volume but WITHOUT
  the `KALEIDOSCOPE_QUERY_TENANT` env var. Assert the
  container exits non-zero AND `query-api.stderr.txt` contains
  the `KALEIDOSCOPE_QUERY_TENANT ... fail-closed` reason on
  stderr. (See issue 005: the documented
  `event=health.startup.refused` tracing event is dropped
  because the binary installs no subscriber; we assert on the
  observable `Err(...)` print path until the subscriber lands.)

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/Q01.stdout.txt`](evidence/Q01.stdout.txt) — runner trace.
- [`evidence/query-api.stderr.txt`](evidence/query-api.stderr.txt) — the binary's stderr (the fail-closed event lives here).

## Issues

- [issue 005](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)
  — query-api emits `tracing::error!(event="health.startup.refused")`
  but installs no tracing subscriber, so the documented
  structured event is dropped silently. Q01 asserts on the
  operator-visible `Err(...)` line from default-main printing
  instead. Tighten this assertion when the subscriber lands.

## Notes

`.no-compose` marker — query-api runs standalone, no compose
stack needed.

Q01 is the cheapest contract on the read side: it does not
require any pre-populated Pulse data. Q02+ build on top by
populating the store and asserting query semantics.
