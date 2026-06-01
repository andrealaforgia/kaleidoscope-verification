# TQ01 — trace-by-id-rejects-malformed-400

## Surface

trace-query-api (Ray traces read HTTP service). Operator/integrator-facing.
First expectation on the TQ surface.

## Behaviour

Given trace-query-api is running with a resolved tenant and a freshly
opened, empty Ray store
When an integrator queries `GET /api/v1/traces/by_id?trace_id=<value>`
Then a malformed `trace_id` is refused with HTTP `400` and a
`status:error` body whose `error` is the single literal class label
`invalid trace_id`, the raw value is never echoed, and the store is
never touched on that path; whereas a well-formed 32-hex `trace_id` is
accepted (`200`, an empty result on the empty store).

Concretely: a 32-char non-hex value and a too-short value both return
`400 invalid trace_id`; a valid 32-hex id returns `200`. The `200`
control proves the `400` is specifically the `parse_trace_id` arm, not
a blanket rejection of the by-id route.

## Source

- trace-query-api graduated to DELIVER; trace-lookup-by-id-v0 (feat
  `3908240`, ADR-0053), tracked as gap N24.
- External contract anchor: `parse_trace_id` and the by-id handler at
  [`crates/trace-query-api/src/lib.rs:233`](https://github.com/andrealaforgia/kaleidoscope/blob/a898e757b88f2c81b311d320c4ec510b879b4928/crates/trace-query-api/src/lib.rs#L233)
  (ADR-0053 Decision 2: exactly 32 hex chars, case-insensitive;
  missing/empty/wrong-length/non-hex collapse to `"invalid trace_id"`,
  raw value never echoed).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-31 UTC at HEAD (`a898e757`). GREEN at first
  attempt: `code_a_nonhex=400`, `code_b_shortlen=400`,
  `code_c_valid=200`; both 400 bodies were
  `{"status":"error","error":"invalid trace_id"}`; neither echoed the
  raw value.
- Method: dockerised harness. trace-query-api is built from the HEAD
  snapshot via the catalogue-authored
  `harness/Dockerfile.trace-query-api` (modelled verbatim on the
  project's `Dockerfile.query-api`; the project ships no Dockerfile for
  this binary, exactly as for log-query-api). The shared driver
  `harness/run-trace-query-api.sh` injects that Dockerfile, builds the
  image, and runs a three-shot scenario against a fresh empty `/data`
  (Ray pillar root) with `KALEIDOSCOPE_TRACE_QUERY_TENANT=acme`, host
  port `19095`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `a898e757`, dirty `yes`, but the dirty set is the dev
  side's in-flight perf-kpi-ci-gating-v0 `tests/*.rs`/`ci.yml` churn;
  zero source under crates/{trace-query-api,ray,query-http-common}/src;
  the build used `git archive HEAD`).
- [`evidence/TQ01.stdout.txt`](evidence/TQ01.stdout.txt) — the three
  HTTP codes and the two 400 bodies.
- [`evidence/tq01-a-nonhex.json`](evidence/tq01-a-nonhex.json),
  [`evidence/tq01-b-shortlen.json`](evidence/tq01-b-shortlen.json) — the
  two `invalid trace_id` 400 envelopes.
- [`evidence/tq01-c-valid.json`](evidence/tq01-c-valid.json) — the
  valid-id `200` (empty result on the empty store).
- [`evidence/trace-query-api.stderr.txt`](evidence/trace-query-api.stderr.txt)
  — the service's container log (empty; no tracing subscriber, the same
  [`issue 005`](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)
  family the implementer is fixing across all three read binaries).
- [`evidence/TQ01.build.txt`](evidence/TQ01.build.txt) — image build log.

## Issues

None directly. trace-query-api shares the issue-005 missing-subscriber
gap (its `trace_query_api_starting` / `listener_bound` /
`health.startup.refused` events drop); TQ01 asserts on HTTP only, so it
is unaffected.

## Notes

Opens the TQ surface (gaps N17/N24). The catalogue stands trace-query-api
up itself via a catalogue-authored Dockerfile, the same recipe proven on
log-query-api in LQ01. Natural next TQ expectations: a by-id round-trip
(a span ingested via the gateway, looked up by its trace_id), the
`/api/v1/traces?service=&start=&end=` window arm, and fails-closed-no-tenant.
Unique high host port (`19095`) per N27.
