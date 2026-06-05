# Q04 — query-api-malformed-promql-honest-400

## Surface

`query-api` `GET /api/v1/query_range`, the `query` (PromQL selector)
parameter. Integrator-facing.

## Behaviour

Given query-api is running
When `query_range` is called with a malformed `query` — an empty string,
an unterminated brace, or unrecognised matcher syntax
Then it returns HTTP 400 with `status:error` and a non-empty
human-readable reason, AND the response body does NOT contain the raw
query text.

## Why this matters

`selector::parse` is the first validation after tenancy and time bounds,
and the store is never touched on the reject path (no ingest needed to
exercise it). Two observable contracts:

1. Honest reject: a bad query is a clean 400 `status:error`, not a panic,
   a 500, or a silent empty 200.
2. No echo: the reason "NEVER echoes the raw query"
   (`crates/query-api/src/selector.rs:75`) — a reflection/injection guard.
   Verified with a distinctive canary token (`ZZLEAKZZ`) in the raw query
   that must be absent from the response body.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`a812193`). GREEN: empty,
  unterminated-brace, and unrecognised-syntax queries each returned
  HTTP 400 `status:error` with a reason; the `ZZLEAKZZ` canary did not
  appear in the body.
- Method: `harness/run-query-api.sh` builds query-api from the HEAD
  snapshot, runs it on a unique high port (19094) over an empty `/data`,
  and fires three malformed queries via `curl -G --data-urlencode`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `a812193`.
- [`evidence/q04-empty.json`](evidence/q04-empty.json),
  [`evidence/q04-brace.json`](evidence/q04-brace.json),
  [`evidence/q04-syntax.json`](evidence/q04-syntax.json) — the three 400
  responses.

## Source

- `crates/query-api/src/selector.rs:78` (`parse`): empty → "expected a
  bare metric name"; unterminated brace → "the label matcher section is
  not closed"; unrecognised → "unrecognised label matcher syntax". The
  reason never echoes the raw query (line 75).
- `crates/query-api/src/lib.rs:184` routes the parse error to a 400.

## Notes

Fourth query-api expectation (Q01 no-tenant, Q02 window-cap, Q03
step-ignored). Pairs with [Q05](../Q05-query-api-invalid-regex-matcher-400/README.md)
(invalid regex matcher, the build_filter 400). The result-size cap
(`MAX_RESULT_ROWS=100_000`) is the remaining query-api reject path; it is
NOT black-box reachable here (it needs >100k distinct series ingested),
so it is left to the in-suite tests, noted in `known-gaps.md`.
