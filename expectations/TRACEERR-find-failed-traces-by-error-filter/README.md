# TRACEERR — find failed traces, distinguishable as failed, by an error filter

## Surface

Surface 3 of the on-screen linked-view goal: a failed request must be FINDABLE
and distinguishable as failed. The per-service trace listing takes an error
filter so "show me what failed" reaches the failed trace in full and leaves
healthy traces out.

## Behaviour

`GET :9092/api/v1/traces?service=<svc>&start=<epoch>&end=<epoch>&error=true`:

- returns ONLY the spans of traces that contain at least one Error-status span,
  and returns ALL spans of each such failed trace (so the failed trace is
  reachable in full, not just its error span);
- EXCLUDES healthy traces in the same service+window;
- `error=false` or absent is unchanged — the listing returns everything;
- a malformed error value -> 400, with no echo of the raw input.

Driven by an external OTel app that emits, under one service name in one window,
a FAILED trace (a checkout span with Error status + a child) AND a HEALTHY trace
(Unset + a child), so the exclusion and the "all spans of the failed trace"
properties are both observable.

## Source

- Named by the implementer as Surface 3 of 3 of the linked-view goal (SHA
  `0052cf9`). The failed trace must be reachable by service+time and marked as
  failed, so a user can locate it before opening the linked view.

## Verification

- Status: `satisfied` on a fresh clean build at `0052cf9`, and confirmed live on
  the clean managed instance (error=true surfaces the bundled failed checkout;
  malformed error -> 400 no echo).
- Transition-proof. RED at `34deafa` (pre-filter): `error=true` was ignored, so
  the healthy trace was NOT excluded — failed traces were not distinguishable.
  GREEN at `0052cf9`: `error=true` returns only the failed checkout trace (all of
  its spans, Error present) and excludes the healthy trace; `error=false`/absent
  unchanged; malformed -> 400 no echo.
- The exclusion-of-healthy property is proven here on a fresh build (the
  single-seed managed instance has only the failed trace, so it cannot show the
  exclusion live); the live instance confirms the failed checkout is surfaced and
  the malformed edge holds.
- Method: `.no-compose`; builds the runtime from the HEAD snapshot, drives the
  external two-trace emitter over OTLP/HTTP, then exercises error=true / false /
  absent / malformed.
- Evidence: `evidence/report.txt` (the two trace ids), `evidence/err_*.json`,
  `evidence/err_malformed.code`.

## Notes

`.no-compose`. Surface 3 of 3 of the linked-view goal (with DEMOCAUSE and
LINKEDVIEW). All three backend surfaces are data/HTTP-level; the on-screen linked
view itself stays gated on the Customer's cold browser run.
