# SAMEORIGIN — every view's data fetch returns JSON on its own origin, not HTML

## Surface

The same-origin glue each on-screen view actually uses: a view served on :9090
(ADR-0078) fetches its data from its OWN origin (:9090/api/v1/...), and that must
return the signal's JSON, not the SPA HTML page. Closes a bug class that has
escaped automation TWICE and been caught only by the Customer — a frontend fetch
resolving to HTML where it expects JSON ("Unexpected token '<'") because a route
is not merged same-origin and falls through to the SPA catch-all (first: the /help
examples landing on the dashboard page; second: the Logs view's /api/v1/logs).

## Why this gap existed

The view e2es MOCK the data (so the view renders), and the substrate checks hit
each signal's OWN port (:9091 logs / :9092 traces return JSON) — but nothing
exercised the served VIEW's real fetch on :9090. This expectation does exactly
that: it probes each view's data route on :9090 and asserts JSON.

## Behaviour

On the view origin :9090, each view's data fetch returns `application/json` with a
JSON body (`[`/`{`):
- metrics: `/api/v1/query_range` — JSON;
- logs: `/api/v1/logs` and `/api/v1/logs?...&body_regex=(?i)...` (the Logs view) — JSON;
- traces: `/api/v1/traces` (the Traces view) — JSON;
- linked detail: `/api/v1/traces/with_logs` — JSON.
Any non-JSON (the SPA HTML page on the deployed stack, or an empty/404 body when a
route is simply not served same-origin) is the bug the view chokes on.

## Verification

- Status: `broken` (RED-grounded; flips GREEN when the logs routes are merged
  same-origin on :9090).
- Grounded RED: 2026-06-16 at the current HEAD on a fresh build. metrics, traces
  and with_logs return JSON on :9090; the LOGS routes return non-JSON (here empty —
  the runtime image does not serve the SPA catch-all, so it surfaces as an unserved
  route rather than the HTML symptom). On the live deployed instance the same gap
  surfaces as the SPA HTML page (content-type text/html), which is what the Logs
  view actually received ("Unexpected token '<'"). Same root cause: the logs routes
  were not extended into the :9090 same-origin merge that traces/metrics have.
- Honest scope: a fresh runtime image reproduces the ROOT CAUSE (logs not merged
  on :9090) as empty/non-JSON; the exact HTML symptom needs the served SPA (the
  deployed stack), which the live instance shows. Both are the same gap; this
  guards it programmatically so the Customer's cold run is the final confirmation,
  not the only net.
- Method: `.no-compose`; builds the runtime from the HEAD snapshot and probes each
  view's data route on :9090.
- Evidence: `evidence/routes.txt` (per-route content-type + body head).

## Notes

`.no-compose`. Recommended by the auditor after the Logs-view failure. Pairs with
the per-signal substrate checks (LOGSEARCH/IDSEARCH on the signal ports) — those
prove the data; this proves the served view's same-origin fetch reaches it. To be
re-confirmed live on the managed instance once delivery merges the logs routes.
