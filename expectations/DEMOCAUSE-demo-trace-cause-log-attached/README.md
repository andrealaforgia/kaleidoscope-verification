# DEMOCAUSE — demo-trace-cause-log-attached

## Surface

Demo-data prerequisite for the on-screen linked view: the BUNDLED demo's
failed-checkout trace must show BOTH halves so a newcomer reading it sees a real
failed checkout — WHERE it failed (a span with error status + a readable message)
and WHY (the attached cause log). The first-party generator emits its failure log
("checkout failed: card declined") INSIDE the demo trace's span AND marks the
failing span with an error status + message.

## Behaviour

After the demo is seeded, the demo trace is discovered from the observable window
(`service=kaleidoscope-demo` on `:9092`) — never hardcoded from the generator's
fixed id — and then:

- WHERE: `GET :9092/api/v1/traces/by_id?trace_id=<demo trace>` returns its spans,
  at least one carrying status code `Error` with a non-empty readable message
  ("checkout failed: card declined");
- WHY: `GET :9091/api/v1/logs?trace_id=<demo trace>` with NO window returns the
  "card declined" cause log carrying that trace id, scoped to that trace.

## Source

- Found while verifying the managed instance and confirmed with the implementer:
  the demo "card declined" log currently lands with `trace_id` null, unattached
  to the demo trace, so a trace->logs view on the demo trace shows no cause. A
  standard external app's traces DO correlate; this is the first-party
  generator's emission. Required so the on-screen linked view can demonstrate the
  WHY on the bundled demo trace, not only on the Customer's own data.

## Verification

- Status: `satisfied` (both halves — WHERE + WHY).
- Grounded GREEN: 2026-06-15 UTC at committed HEAD `622fe05`, AND confirmed live on
  the managed instance. On a fresh committed-tree build the discovered demo trace
  (`4bf92f35…`) shows a span with status `Error` and the readable message
  "checkout failed: card declined" (WHERE), and returns that cause log by trace id
  with no window (WHY), scoped to that trace. On the live managed instance
  (delivery re-seeded append-only): the demo trace has a span with Error status +
  that message among its spans, and the cause log attached by id. (The demo-data
  fixes were in the generator/seed; the runtime image is unchanged — correct.)
- WHY-only milestone: grounded GREEN at HEAD `2ea0077` (cause log attached).
  Previously `broken` at `1a117b3` — the demo trace carried no cause log (the "card
  declined" log landed with `trace_id` null) and no error span (spans were Unset).
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
