# LINKEDVIEW — the demo failed checkout, whole, in the view's one call

## Surface

The DATA LINKAGE the on-screen linked view renders, asserted on the endpoint the
view actually calls. It composes DEMOCAUSE (the bundled demo must be a COHERENT
failed checkout) and WITHLOGS (one call returns spans + logs together) onto the
DEMO trace: a single `GET :9092/api/v1/traces/with_logs?trace_id=<demo trace>`
must return the whole coherent failed-checkout story in ONE response.

This is NOT the on-screen view. The linked VIEW is proven only by the Customer's
COLD BROWSER RUN on a clean managed instance. This expectation proves the data
the view would render is coherent and complete in the one call it makes — the
backend half is "data linkage ready", never "the view is nearly done".

## Behaviour

After the demo is seeded, the demo trace is discovered from the observable window
(`service=kaleidoscope-demo`), never hardcoded, then the view's single call
returns one `{trace_id, spans, logs}` object in which:

- WHERE: a checkout-shaped span carries Error status with a readable message —
  not a generic `GET /api/v1/query_range` span with a "checkout failed" message
  bolted on;
- WHY: that span's cause log ("card declined") is present in the SAME response,
  scoped to the trace;
- COHERENT: exactly one cause copy on the demo trace, and no orphaned
  (trace_id-null) cause copies anywhere in the window.

## Source

- Composed from the two backend surfaces of the linked-view goal (DEMOCAUSE +
  WITHLOGS) onto the endpoint the view consumes, so the linkage is proven on the
  bundled demo the view demonstrates — not only on a clean external trace.

## Verification

- Status: `satisfied` on a FRESH CLEAN build (`34deafa` and re-confirmed at the
  live SHA `0052cf9`), AND independently confirmed LIVE on the fresh clean managed
  instance (2026-06-15): the view's one `with_logs` call on the demo trace returns
  the whole coherent story scoped, one checkout-shaped Error span + its one clean
  cause log. The Customer's cold browser run remains the on-screen view's done-gate.
- Grounded RED first: 2026-06-15 UTC at committed `83f4d84`, on a fresh clean
  build. The discovered demo trace's only failing span was `GET /api/v1/query_range`
  carrying "checkout failed: card declined" — incoherent: the view would show a
  generic query "failing" with a checkout error.
- Flipped GREEN: 2026-06-15 UTC at committed `34deafa`, on a FRESH clean build.
  The view's single `with_logs` call on the demo trace returns, in ONE response, a
  checkout-shaped Error span (`POST /api/v1/checkout`, "checkout failed: card
  declined") = WHERE AND its single clean cause log = WHY, both scoped, no
  orphaned/duplicate copies.
- Verify on a FRESH CLEAN instance, never the current managed instance (it
  carries stale/duplicate residue from when the Customer operated it; a green on
  polluted data proves nothing). Build-from-HEAD is clean by construction; the
  managed-instance confirmation needs a fresh stand-up.
- Method: `.no-compose`; builds runtime + first-party generator from the HEAD
  snapshot, boots one runtime, seeds the demo, discovers the demo trace, calls
  `with_logs` by that id, and also reads all logs in the window to catch
  orphaned/duplicate cause copies.
- Evidence: `evidence/window.json`, `evidence/demo.txt`,
  `evidence/with_logs.json`, `evidence/all_logs.json`.

## Notes

`.no-compose`. The backend data-linkage acceptance for the on-screen linked view.
Depends on DEMOCAUSE (demo coherence) landing; once green on a clean instance,
the data the view renders is verified, and the view itself remains gated on the
Customer's cold browser run.
