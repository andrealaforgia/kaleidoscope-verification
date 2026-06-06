# LQ08 — logs-parameter-validation-400s

## Surface

`crates/log-query-api` binary (`/api/v1/logs` parameter validation).

## Behaviour

log-query-api validates query parameters and returns `400` (never `500`)
on each malformed case, before touching the store:
- unknown `min_severity` (e.g. `LOUD`) → 400 (UC-LOG-004);
- empty `body_contains=` → 400 (UC-LOG-006);
- oversized `body_contains` (> 1024 bytes) → 400 (UC-LOG-007);
- uncompilable `body_regex` (e.g. `[`) → 400, not 500 (UC-LOG-009);
- window `> 86400 s` → 400 (UC-LOG-015).

A valid baseline request returns 200. Validation precedes the query, so
an empty store suffices.

## Source

- External contract anchor: log-query-api request validation.
- Use-case anchor: `kaleidoscope-usecases` UC-LOG-004/006/007/009/015.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`6a54ae1`).
- Method: stand up log-query-api (tenant=acme, empty store); fire each
  malformed query → 400; valid baseline → 200.

## Evidence

- [`evidence/codes.txt`](evidence/codes.txt) — per-case HTTP codes.

## Issues

None.

## Notes

`.no-compose` marker; built via `harness/run-log-query-api.sh`. The result
cap (UC-LOG-016, `> 100000`) is NOT black-box reachable (needs >100k
matching records ingested); left to in-suite tests — see `known-gaps.md`.
