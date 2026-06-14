# FIXB2 — query-apis-accept-rfc3339

## Surface

Sprint item FIX-B.2 (onboarding ergonomics). The three query APIs' timestamp
handling, observed uniformly across :9090 / :9091 / :9092.

## Behaviour

Each query API accepts `start`/`end` as EITHER RFC3339 (`2026-06-14T00:00:00Z`)
OR unix-seconds, and an unparseable timestamp returns a `400` whose message
NAMES both accepted formats — not the bare "is not a number".

- `:9090 /api/v1/query_range`, `:9091 /api/v1/logs`, `:9092 /api/v1/traces`:
  unix-seconds window → `200`; RFC3339 window → `200`; unparseable → `400`
  whose body names RFC3339 AND unix-seconds.

## Source

- Sprint requirement FIX-B.2 (PO, agreed with Customer). Observable contract
  only: the three query APIs accept the same timestamp formats and give the same
  parse error.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `eac5f2f` (fix(query-http-common)
  FIX-B.2). On all three APIs (:9090/:9091/:9092): unix-seconds → `200`, RFC3339
  → `200`, unparseable → `400` with body `{"status":"error","error":"invalid
  time bounds: start must be RFC3339 (e.g. 2026-06-14T17:00:00Z) or unix
  seconds"}` — names both accepted formats, no raw-value echo. Flipped from RED
  on the implementer's commit, exactly as the transition-proof expectation was
  pre-authored.
- Previously `broken`: grounded RED 2026-06-14 at HEAD `0d398b9` — RFC3339 → `400`
  on all three with the bare `"start is not a number"` (no format named).
- Method: `harness/run-kaleidoscope-runtime.sh` builds the runtime from the HEAD
  snapshot; the runner boots one runtime and probes the three APIs with a
  unix-seconds window, an RFC3339 window, and an unparseable value.

## Notes

`.no-compose`: FIXB2 manages its own runtime container. Generator-independent
(runtime only). Pre-authored RED so it flips GREEN the moment the implementer
commits the fix; companion to FIX-B.1 (the `/help` getting-started endpoint).
