# LQ04 — logs-pagination-limit-offset

## Surface

kaleidoscope-gateway (OTLP receiver, Lumen sink) + log-query-api
(`/api/v1/logs` over Lumen). End-to-end, operator/integrator-facing.

## Behaviour

Given a set of log records is ingested through the gateway into the
durable Lumen store and read back through log-query-api over the same
store and tenant
When the read is parameterised with `limit` and `offset`
Then the endpoint pages the stable-ordered, post-filter result set with
`skip(offset).take(limit)` semantics and the documented cap-then-slice
order:

- `limit=3` returns exactly the first three records (the head page),
  identical to `full[0:3]` by `observed_time_unix_nano`.
- `offset=3&limit=3` returns exactly records `full[3:6]`, contiguous with
  and disjoint from the head page.
- `limit=0` is refused with `400` and the literal reason `invalid limit`
  (the store is never queried on that path).
- An offset past the end of the result set returns `200` with the empty
  array `[]`, NOT an error.

This pins the new pagination contract at the running surface, including
its two boundary arms (the validation 400 and the empty-page-not-error
rule).

## Source

- kaleidoscope `5a8b330..4e4060e` (observed during cycle 33):
  log-query-pagination-v0 landed as a real feature, feat `47fc5ef`
  ("limit and offset pagination on /api/v1/logs"), design `489f3ed`
  ("handler-side slice, cap before slice").
- External contract anchor: ADR-0057, implemented at
  [`crates/log-query-api/src/lib.rs:349`](https://github.com/andrealaforgia/kaleidoscope/blob/4e4060e522420e95ea738424bf4bbabe883843e3/crates/log-query-api/src/lib.rs#L349)
  (`records.into_iter().skip(offset).take(limit).collect()`, applied
  AFTER the result-size cap), with `parse_limit` rejecting `0`/negative/
  non-numeric/over-cap as `invalid limit` and `parse_offset` accepting
  `0` and imposing no upper cap.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-30 UTC at HEAD (`4e4060e`, clean). GREEN at
  first attempt: total 21 records ingested; `limit=3` == `full[0:3]`;
  `offset=3&limit=3` == `full[3:6]` (disjoint from page 1); `limit=0` →
  `400 invalid limit`; `offset=1000000` → `[]`.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14320`, ~20 OTLP/HTTP log records (`telemetrygen` rate 10 over
  2 s, `--body lq04-page-body`), SIGTERM to flush Lumen, then
  log-query-api on the SAME `/data` (host port `19093`). The full
  unpaginated query establishes the ground-truth order; each page is
  compared to a slice of it by `observed_time_unix_nano` (the stable
  sort key and per-record identity).

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `4e4060e`, dirty `no`).
- [`evidence/lq04-full.json`](evidence/lq04-full.json) — the full ordered
  result (ground truth).
- [`evidence/lq04-p1.json`](evidence/lq04-p1.json),
  [`evidence/lq04-p2.json`](evidence/lq04-p2.json) — the two pages.
- [`evidence/lq04-inv.json`](evidence/lq04-inv.json) — the `limit=0`
  `400 invalid limit` envelope.
- [`evidence/lq04-past.json`](evidence/lq04-past.json) — the
  offset-past-end empty array.
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt),
  [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt).

## Issues

None.

## Notes

First expectation drawn from a feature that landed DURING the cycle that
caught it: cycle 33 opened with HEAD at `5a8b330` (only CI work), but the
dev side committed `5a8b330..4e4060e` mid-cycle, bringing the pagination
feature. Verified at the new clean HEAD. Binds unique high host ports
(`14320`, `19093`) per N27. The result-cap-before-slice order (the cap is
measured on the pre-slice vector) is asserted indirectly here; a direct
test would need a seed exceeding `MAX_RESULT_ROWS`, a heavier fixture
left for an LQ-cap expectation alongside the durability set (#17).
