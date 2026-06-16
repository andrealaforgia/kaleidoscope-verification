# LOGSEARCH — symptom-path log search discriminates the failure out of noise

## Surface

The DATA SUBSTRATE behind iteration 2's symptom path: searching logs in their own
right, over a time window, by text-in-body and by severity, must pick the one
"declined" failure out of realistic noise — and the matched log must carry its
trace_id so the on-screen pivot needs no typed id.

Grounded finding (2026-06-16): the consolidated runtime ALREADY supports
`body_contains` (ADR-0055) and `min_severity` (ADR-0052) on its logs router, so the
symptom-path SEARCH is built. Iteration 2's net-new work is the on-screen Logs VIEW
+ the pivot + a noisy bundled demo, not the search backend.

## Behaviour (verified GREEN)

Against the shared noisy emitter (`_emitters/noisy_app.py`, ~12-15 logs across 5
customers and 4 request types, mostly INFO, exactly one ERROR "declined"):

- `GET :9091/api/v1/logs?...&body_contains=declined` -> exactly the one declined
  log out of the noise, carrying its trace_id;
- it is CASE-SENSITIVE: `body_contains=Declined` (capital) -> 0;
- `GET :9091/api/v1/logs?...&min_severity=error` -> exactly the one error log out
  of the INFO noise;
- PIVOT: the matched log's trace_id resolves to WHERE (an Error span) + WHY (the
  cause log) via with_logs — reached from the log, no typed id.

Note (constraint, from source DD4): `body_contains` and `min_severity` are mutually
exclusive at slice 01 — search by text OR by severity, not both combined.

## Verification

- Status: `satisfied` at the current HEAD on a fresh build.
- Method: `.no-compose`; builds the runtime from the HEAD snapshot, runs it
  overlay-OFF (KALEIDOSCOPE_DEMO_OVERLAY=0) so the default-on demo overlay does not
  inject a second declined, drives the noisy emitter on a NON-demo service
  (bea-shop), and exercises the text/severity/case/pivot queries.
- Evidence: `evidence/all_logs.json`, `bc_declined.json`, `bc_capital.json`,
  `sev_error.json`, `pivot_withlogs.json`, `declined.txt`.

## Notes

`.no-compose`. The search + pivot DATA the on-screen Logs view rests on. The Logs
view rendering, the search controls and the pivot click are client-rendered —
proven only by the Customer's cold browser run; this is "search + pivot data
ready", never "the view is done". The bundled demo still needs a noisy log set (on
the overlay's synthesised side) so a newcomer's cold run discriminates rather than
finding a sole record.
