# FIXB1 — help-getting-started-endpoint

## Surface

Sprint item FIX-B.1 (onboarding / API discoverability). A curl-friendly
getting-started endpoint on the runtime.

## Behaviour

`GET :9090/help` returns `200` plain text with the four example curls
(`/api/v1/query_range`, `/api/v1/logs`, `/api/v1/traces` service-window,
`/api/v1/traces/by_id`) and the accepted time format. It is an EXACT router
route that wins over the Prism SPA fallback, so `GET /` stays the SPA while
`/help` serves the help text — and it answers even when no static dir is set
(this runtime has none), proving `/help` is not gated behind the SPA fallback.

## Source

- Sprint requirement FIX-B.1 (PO, confirmed route + content). The Customer
  reads no code and needs curl examples; today there is no index/help and the
  Prism SPA occupies `/` as the fallback.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `2fd4daa` (FIX-B.1). `GET
  :9090/help` → `200` plain text: "Kaleidoscope query API — usage" with the four
  example curls (`/api/v1/query_range`, `/api/v1/logs`, `/api/v1/traces`,
  `/api/v1/traces/by_id`) and "Accepted time format: RFC3339 … or unix seconds".
  Flipped from RED on the implementer's commit, exactly as pre-authored.
- Previously `broken`: grounded RED 2026-06-14 at HEAD `0d398b9` — `GET /help` →
  `404` (no such route).
- Method: `harness/run-kaleidoscope-runtime.sh` builds the runtime from the HEAD
  snapshot; the runner boots one runtime and probes `GET /help`.

## Notes

`.no-compose`: FIXB1 manages its own runtime container. Generator-independent.
PO note: when PG-2 lands, `/help` also gets the `/api/v1/logs?trace_id=...`
curl. Companion to FIXB2 (RFC3339 timestamps), which the `/help` text should
reflect in its stated time format.
