# Q06 — query-api-label-matchers-honoured

## Surface

`query-api` `GET /api/v1/query_range`, label matchers in the `query`
selector. Integrator-facing.

## Behaviour

Given one OTLP metric `gen` ingested via the gateway into Pulse and read
back through query-api
When `query_range` is called over a fixed window with a SATISFIED matcher
(`gen{__name__="gen"}`) and then a CONTRADICTING matcher
(`gen{__name__="q06zznomatch"}`)
Then the satisfied matcher returns the series and the contradicting
matcher returns an EMPTY result — the matcher changes the result.

## Why this matters (the Q03 contrast)

This is the deliberate counterpart to
[Q03](../Q03-query-api-step-accepted-but-ignored/README.md). Q03 shows
`step` is IGNORED (two queries differing only in step return identical
results). Q06 shows label matchers are HONOURED (two queries differing
only in a matcher return different results). Together they pin which query
parameters affect the response and which do not, so an integrator is not
surprised either way.

Matchers are applied in `keep_row` over the merged label set
(`resource_attributes ∪ point.attributes ∪ {__name__}`) before
`to_matrix`, so `__name__` — always present and authoritative — is a valid
matcher target; the same mechanism applies to attribute labels.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`dc826da`). GREEN: plain `gen` =
  1 series, `gen{__name__="gen"}` = 1 series (satisfied matcher keeps the
  row), `gen{__name__="q06zznomatch"}` = 0 series (contradicting matcher
  drops it). All three `status=success`.
- Method: `harness/run-eg.sh` (gateway + query-api from the HEAD
  snapshot). telemetrygen sends one counter `gen` to the gateway on a
  unique high port (14334); the gateway is SIGTERMed to flush Pulse;
  query-api reopens the same `/data` on port 19099; three `query_range`
  calls over one fixed window (plain, satisfied matcher, contradicting
  matcher) are compared by `.data.result` length.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `dc826da`.
- [`evidence/q06-plain.json`](evidence/q06-plain.json),
  [`evidence/q06-match.json`](evidence/q06-match.json),
  [`evidence/q06-nomatch.json`](evidence/q06-nomatch.json) — the three
  responses (1 / 1 / 0 series).

## Source

- `crates/query-api/src/matrix.rs` (`keep_row` → `merge_labels` includes
  `__name__`; matchers applied before `to_matrix`).
- `crates/query-api/src/lib.rs:188` (`build_filter`) compiles the matchers
  once before the row scan.

## Notes

Uses `__name__` as the always-present matcher target for a deterministic
match/nomatch; attribute labels (e.g. a resource `service.name`) filter by
the same code path. Sixth query-api expectation; with Q04/Q05 (reject
no-echo) and Q01-Q03 it gives query-api broad black-box coverage. The
result-size cap stays out of reach (needs >100k series) and is credited
to in-suite tests.
