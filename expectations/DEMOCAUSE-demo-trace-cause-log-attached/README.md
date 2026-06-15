# DEMOCAUSE — demo-trace-cause-log-attached

## Surface

Demo-data prerequisite for the on-screen linked view: the BUNDLED demo's
failed-checkout trace must carry its CAUSE log, so a "trace -> its logs" view on
the demo trace shows WHY it failed. The first-party generator must emit its
failure log ("checkout failed: card declined") INSIDE the demo trace's span.

## Behaviour

After the demo is seeded, the demo trace is discovered from the observable window
(`service=kaleidoscope-demo` on `:9092`) — never hardcoded from the generator's
fixed id — and then `GET :9091/api/v1/logs?trace_id=<that demo trace>` with NO
window returns the "card declined" cause log carrying that trace id, scoped to
that trace.

## Source

- Found while verifying the managed instance and confirmed with the implementer:
  the demo "card declined" log currently lands with `trace_id` null, unattached
  to the demo trace, so a trace->logs view on the demo trace shows no cause. A
  standard external app's traces DO correlate; this is the first-party
  generator's emission. Required so the on-screen linked view can demonstrate the
  WHY on the bundled demo trace, not only on the Customer's own data.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-15 UTC at committed HEAD `2ea0077`, AND confirmed live
  on the managed instance after delivery re-seeded it with the new generator. On
  a fresh committed-tree build the discovered demo trace (`4bf92f35…`) returns its
  "checkout failed: card declined" cause log by trace id with no window, scoped to
  that trace. On the live managed instance: logs-by-trace_id for the demo trace
  returns exactly 1 log, the declined cause, scoped. (The fix was in the
  generator, kaleidoscope-telemetrygen; the runtime image is unchanged — correct.)
- Previously `broken`: grounded RED 2026-06-15 at committed HEAD `1a117b3` — the
  demo trace carried no cause log (logs-by-trace_id returned 0; the "card declined"
  log landed with `trace_id` null, unattached).
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
