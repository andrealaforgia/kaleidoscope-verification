# DEMOCAUSE — demo-trace-cause-log-attached

## Surface

Demo-data prerequisite for the on-screen linked view: the BUNDLED demo's
failed-checkout trace must tell a COHERENT failed checkout a newcomer can walk —
not just carry the mechanical pieces. She opens it and reads a real failed
checkout: WHERE (a CHECKOUT-shaped failing span with error status + a readable
message) and WHY (its cause log attached to THAT trace), with no orphaned or
duplicate cause-log copies floating in the data.

## Behaviour

After the demo is seeded, the demo trace is discovered from the observable window
(`service=kaleidoscope-demo` on `:9092`) — never hardcoded from the generator's
fixed id — and then:

- WHERE (coherent): `GET :9092/api/v1/traces/by_id?trace_id=<demo trace>` returns
  a span carrying status `Error` with a readable message, AND that failing span
  represents a CHECKOUT (its name references a checkout) — not a generic
  `GET /api/v1/query_range` span with a "checkout failed" message bolted on;
- WHY: `GET :9091/api/v1/logs?trace_id=<demo trace>` (no window) returns the
  "card declined" cause log scoped to that trace;
- COHERENT, single copy: across the window, the "card declined" cause log is a
  SINGLE copy attached to the demo trace — no orphaned (trace_id null) copies, no
  duplicates, not attached to any non-demo trace.

## Source

- Found while verifying the managed instance and confirmed with the implementer:
  the demo "card declined" log currently lands with `trace_id` null, unattached
  to the demo trace, so a trace->logs view on the demo trace shows no cause. A
  standard external app's traces DO correlate; this is the first-party
  generator's emission. Required so the on-screen linked view can demonstrate the
  WHY on the bundled demo trace, not only on the Customer's own data.

## Verification

- Status: `broken` (strengthened to COHERENCE; my earlier "satisfied" was a
  mechanical green and is corrected here).
- Grounded RED: 2026-06-15 UTC at committed HEAD `622fe05`, on a FRESH clean build.
  The demo trace's only span is `GET /api/v1/query_range`, and the error span is
  that same query span carrying the message "checkout failed: card declined" — so
  a newcomer opening it sees a generic query "failing" with a checkout error,
  which does NOT read as a failed checkout. Flips GREEN when the demo trace is
  checkout-shaped (the failing span represents the checkout), its cause log a
  single clean copy attached to it, no orphaned/duplicate copies.
- Earlier MECHANICAL greens (now seen as insufficient): the cause log was
  retrievable by the demo trace id (HEAD `2ea0077`) and an Error-status span
  existed (HEAD `622fe05`) — but neither asserted a COHERENT failed-checkout
  story, and both were checked against the (polluted) live instance. The Customer
  reported the bundled demo doesn't hold together: four "checkout failed" copies,
  three orphaned, the attached one on a generic `query_range` span. The auditor
  flagged the mechanical-vs-coherent gap; this expectation now asserts the story.
- Verify on a FRESH CLEAN instance: the demo coherence + single-copy assertions
  must be checked against a clean instance delivery stands up, never the current
  managed instance, which carries stale/duplicate residue from when the Customer
  operated it (a green on polluted data proves nothing). The build-from-HEAD run
  is clean by construction; the managed-instance confirmation needs a fresh stand-up.
- Method: `.no-compose`; builds runtime + first-party generator from the HEAD
  snapshot, boots one runtime, seeds the demo, discovers the demo trace from the
  window, and queries its logs by id with no window.
- To be re-confirmed on the LIVE managed instance after delivery re-seeds it
  (the goal is delivered on the instance she's handed).
- Evidence: `evidence/window.json` (discovered demo trace), `evidence/demo.txt`,
  `evidence/cause_logs.json` (the by-id logs).

## Notes

`.no-compose`. Companion to MANAGEDINSTANCE (the instance this demo lives on) and
a building block for the next goal (the on-screen linked trace+logs view): the
linked view's demo can only show the WHY once this is green.
