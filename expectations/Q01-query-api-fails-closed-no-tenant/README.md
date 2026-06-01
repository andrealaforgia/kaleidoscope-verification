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
- Last verified: 2026-06-01 UTC at HEAD (`2663eb5`) — TIGHTENED onto
  the structured event. Since read-api-tracing-subscriber-v0 landed,
  query-api installs `query_http_common::init_tracing`, so the
  fail-closed arm emits a STRUCTURED JSON `health.startup.refused`
  (level ERROR) on stderr before the non-zero exit. Observed verbatim:
  `{"level":"ERROR","event":"health.startup.refused","reason":"KALEIDOSCOPE_QUERY_TENANT is unset or empty (fail-closed)"}`.
  The assertion now `jq`-parses that event (event name + ERROR level +
  reason), not just the bare `Err()` text. Resolves the read-tier part
  of issue 005.
- Earlier `satisfied`: 2026-05-23 at `0c1d66b` (asserting the bare
  `Err()` text, the only observable signal before the subscriber).
- Method: `harness/run-query-api.sh` builds the query-api runtime image
  from the snapshot's `Dockerfile.query-api`, then `docker run` with a
  writable /data volume but WITHOUT the `KALEIDOSCOPE_QUERY_TENANT` env
  var. Assert the container exits non-zero AND the structured
  `health.startup.refused` JSON event (ERROR, tenant fail-closed reason)
  is present on stderr, plus the bare `Err()` line as a belt-and-braces
  signal.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/Q01.stdout.txt`](evidence/Q01.stdout.txt) — runner trace.
- [`evidence/query-api.stderr.txt`](evidence/query-api.stderr.txt) — the binary's stderr (the fail-closed event lives here).

## Issues

- [issue 005](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)
  — the read-tier part is RESOLVED at `2663eb5`: query-api now
  installs the subscriber and Q01 asserts the structured
  `health.startup.refused` JSON event (tightened, see Verification).
  The issue stays `partial` only for the separate kaleidoscope-gateway
  binary (G01), which still has no subscriber.

## Notes

`.no-compose` marker — query-api runs standalone, no compose
stack needed.

Q01 is the cheapest contract on the read side: it does not
require any pre-populated Pulse data. Q02+ build on top by
populating the store and asserting query semantics.
