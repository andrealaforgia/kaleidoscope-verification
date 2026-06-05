# Q05 — query-api-invalid-regex-matcher-400

## Surface

`query-api` `GET /api/v1/query_range`, a `=~` (regex) label matcher in the
`query` selector. Integrator-facing.

## Behaviour

Given query-api is running
When `query_range` is called with `gen{job=~"<bad-regex>"}` whose pattern
is an unclosed character class
Then it returns HTTP 400 with `status:error` and a non-empty reason
naming the matcher invalid, AND the response body does NOT contain the
offending pattern.

## Why this matters

A `=~` matcher parses to a `Matches` matcher carrying a raw regex, which
is compiled filter-side BEFORE the store is queried (`build_filter`,
ADR-0046 Decision 3). "A compile failure is the single origin of the
invalid-regex 400... the reason names the matcher invalid and never
echoes the offending pattern, the raw query, or a forwarded header"
(`crates/query-api/src/lib.rs:191`). Two observable contracts, as in Q04:
honest 400 (not a panic/500/empty-200) and no echo of the pattern
(verified with a `ZZRELEAKZZ` canary inside the bad regex).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`a812193`). GREEN:
  `gen{job=~"ZZRELEAKZZ["}` returned HTTP 400 `status:error` with a
  reason; the `ZZRELEAKZZ` pattern token did not appear in the body.
- Method: `harness/run-query-api.sh` builds query-api from the HEAD
  snapshot, runs it on a unique high port (19095) over an empty `/data`,
  and fires the bad-regex query via `curl -G --data-urlencode`. The
  empty store suffices because compilation precedes the store query.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `a812193`.
- [`evidence/q05-response.json`](evidence/q05-response.json) — the 400.

## Source

- `crates/query-api/src/selector.rs:189` parses `=~` to `MatchOp::Matches`
  with the raw pattern; `crates/query-api/src/lib.rs:188` (`build_filter`)
  compiles it and routes a compile failure to a 400 that never echoes the
  pattern.

## Notes

Pairs with [Q04](../Q04-query-api-malformed-promql-honest-400/README.md):
Q04 is the parse-stage 400 (bad selector syntax), Q05 the
compile-stage 400 (valid syntax, bad regex). Together they pin both
query-validation reject points with the no-echo guarantee.
