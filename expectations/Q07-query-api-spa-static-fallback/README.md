# Q07 — query-api-spa-static-fallback

## Surface

`query-api` HTTP server, the static-bundle fallback gated on
`KALEIDOSCOPE_QUERY_STATIC_DIR` (DD6, ADR-0042). Integrator-facing
(Prism's SPA served same-origin with the API).

## Behaviour

Given query-api started with `KALEIDOSCOPE_QUERY_STATIC_DIR` pointing at a
bundle dir containing `index.html` and `config.json`
When various paths are requested
Then an existing file (`/config.json`) is served directly (200, its
bytes); an unknown non-API deep link (`/dashboards/42`) falls back to
`index.html` with a 200 (NOT a 404), so the SPA router owns deep links;
and `/api/v1/query_range` still resolves to the API, not the static
fallback. With `KALEIDOSCOPE_QUERY_STATIC_DIR` unset, the same deep link
is a 404 (API-only).

## Why this matters

The bundle is served from the same origin as `/api/v1`, removing the need
for CORS. Two non-obvious contracts an integrator relies on: the exact API
route WINS over the fallback (so the SPA never shadows the API), and an
unknown path is the SPA index (200), not a 404, so client-side deep links
work on refresh.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`d7dab93`). GREEN:
  `code_file=200` (config.json bytes served), `code_deeplink=200`
  (`/dashboards/42` → index.html), `code_api=200` (`status=success`, not
  html), `code_deeplink_nostatic=404` (negative control, no static dir).
- Method: self-contained (`.no-compose`). `harness/run-query-api.sh`
  builds query-api from the HEAD snapshot; the runner starts one instance
  with `KALEIDOSCOPE_QUERY_STATIC_DIR=/static` (a mounted dir with sentinel
  `index.html` + `config.json`) on port 19100 and probes the three paths,
  then a second instance with no static dir on 19101 for the 404 control.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `d7dab93`.
- [`evidence/config.out`](evidence/config.out) (file bytes),
  [`evidence/deeplink.out`](evidence/deeplink.out) (index fallback),
  [`evidence/api.out`](evidence/api.out) (API JSON),
  [`evidence/deeplink-nostatic.out`](evidence/deeplink-nostatic.out) (404).
- [`static/index.html`](static/index.html), [`static/config.json`](static/config.json).

## Source

- `crates/query-api/src/lib.rs:112` (`router`: exact `.route` wins over
  `.fallback_service`), `:130` (`spa_static_service`: `ServeDir` with an
  `index.html` fallback, 200 not 404).
- `crates/query-api/src/main.rs:101` reads `KALEIDOSCOPE_QUERY_STATIC_DIR`
  (set/non-empty → Some, unset/empty → None).

## Notes

Seventh query-api expectation. Complements the query behaviour set
(Q01-Q06) with the transport/serving contract. Uses sentinel files rather
than Prism's real bundle, since the behaviour under test is the routing
(file vs index-fallback vs API), not Prism's contents.
