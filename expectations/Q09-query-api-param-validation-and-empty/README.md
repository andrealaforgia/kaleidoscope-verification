# Q09 — query-api-param-validation-and-empty

## Surface

`crates/query-api` binary (`/api/v1/query_range` request handling).

## Behaviour

Request-shape contracts that need no ingested data:
- a query matching nothing is `status=success` with an empty result, not
  404/500 (UC-MET-007);
- non-numeric `start`/`end` → 400 (UC-MET-014);
- float-tolerant epoch seconds (`start=1.5`) parse without error → 200
  (UC-MET-017);
- aggregation/rate functions are unsupported at v0: `rate(up[5m])` → 400,
  the honest raw-selectors-only surface (UC-MET-018).

## Source

- External contract anchor: query-api request validation + v0 PromQL
  surface (raw selectors only).
- Use-case anchor: `kaleidoscope-usecases` UC-MET-007/014/017/018.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`6a54ae1`).
- Method: stand up query-api (tenant=acme, empty store); nonexistent
  metric → 200 success empty; `start=abc` → 400; `start=1.5` (small
  window) → 200; `rate(up[5m])` → 400.

## Evidence

- [`evidence/Q09.stdout.txt`](evidence/Q09.stdout.txt) — per-case codes.
- [`evidence/empty.json`](evidence/empty.json), [`evidence/rate.json`](evidence/rate.json).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-query-api.sh`. The float test uses a
small window so the only thing under test is epoch parsing, not the
86400 s window cap (UC-MET-010, owned by Q02). UC-MET-009 (step ignored) is
Q03; UC-MET-011 (result cap >100k) and UC-MET-015 (store-read 500) are not
black-box reachable.
