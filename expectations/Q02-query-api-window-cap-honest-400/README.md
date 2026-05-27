# Q02 — query-api-window-cap-honest-400

## Surface

`query-api` operator binary (port 9090). Operator-facing.

## Behaviour

`GET /api/v1/query_range?query=<name>&start=<s>&end=<e>&step=15s`
with `(end - start) > 86400` (i.e. a time window larger than
the 24 h cap) is refused with HTTP 400 and a Prometheus-style
`{"status":"error","error":"window exceeds 86400 seconds"}`
body. The store is NEVER queried on the refusal path; the
reason names the cap value verbatim, not the requested
values. This is the "honest 400, not silent truncation"
contract from ADR-0050 Decision 1 / D5.

## Source

- External contract anchor: commit `b71ad8a`
  ("feat(read-caps): honest 400 for oversized window or result
  on the three read APIs"). ADR-0050 Decision 1 / D5.
- Code: `crates/query-api/src/lib.rs::MAX_WINDOW_SECONDS`
  (= 86400) and the early-return arm
  `if end_secs.saturating_sub(start_secs) > MAX_WINDOW_SECONDS`
  before the store is touched.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-27 UTC at HEAD (`b71ad8a`).
- Method: `harness/run-query-api.sh` builds the query-api
  image, starts the container with `KALEIDOSCOPE_QUERY_TENANT=acme`,
  curls a window of 86401 seconds (one second over the cap),
  and asserts HTTP 400 + `.status == "error"` + `.error`
  contains `"86400"`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/Q02.stdout.txt`](evidence/Q02.stdout.txt) — runner trace.
- [`evidence/q02-response.json`](evidence/q02-response.json) — observed `{"error":"window exceeds 86400 seconds","status":"error"}`.

## Issues

None.

## Notes

`.no-compose` marker. Q02 is the second Q-prefix contract;
Q01 covers fails-closed-no-tenant, Q02 covers the
honest-not-truncating cap. The result-size cap (100k rows)
is the natural sibling Q03 — request a small window with
synthetic data forcing > 100k points and assert the same
shape. Deferred until a fixture can produce that load.

The contract is anchored at the lib seam (the cap check
happens before the store is queried), not at any single
binary. Equivalent expectations on the log-query-api and
trace-query-api would open when those binaries gain a
packaging Dockerfile (see N16 / N17).
