# MANAGEDINSTANCE — customer-running-instance

## Surface

Process change (Andrea, 2026-06-15): the Customer stops operating Kaleidoscope —
she never builds, ups, seeds, resets, or rebuilds. Delivery owns a managed,
always-current running instance she is handed. This is the verifier's
INDEPENDENT check of that instance's observable contract (it probes the live
instance; it does not build or own it — the party that owns/operates the instance
must not be the one verifying it).

## Behaviour

At the FIXED address the Customer is given:

- the dashboard answers — `GET http://localhost:9090/` returns `200` HTML;
- sample/demo telemetry is present WITHOUT her building anything — a
  `kaleidoscope-demo` trace is queryable on `:9092` and the `request_count`
  metric returns a series on `:9090` (delivery placed it via a pre-built path,
  not a source build);
- her two and only actions work end to end: an OTLP export to the ingest address
  (`:4318`) round-trips through the query interface CORRELATED — the trace comes
  back by id on `:9092`, and its in-span log is retrievable by trace id on
  `:9091` with NO time window (which also confirms the instance is on the current
  build, since no-window logs-by-trace_id is the current-build behaviour).

The demo trace is DISCOVERED from the observable window
(`service=kaleidoscope-demo`), never hardcoded from the generator's fixed id.

## Source

- PO/Andrea managed-instance delivery duty (2026-06-15). She is blocked until the
  instance exists, by design. Verifier defines + independently verifies the
  observable contract; delivery (the implementer, who operates and redeploys the
  instance) owns standing it up and keeping it current. Companion to the next
  goal, the on-screen linked trace+logs view, which will be verified ON this
  instance.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-15 UTC against the LIVE managed instance (built from
  current source, `1a117b3`). Dashboard `:9090/` -> 200 HTML; demo trace
  `4bf92f35…` queryable + `request_count` 1 series (no source build); an OTLP
  export (`6832732c…`) round-tripped correlated — 2 spans by id, its in-span log
  retrievable by id with no window.
- Re-run after every redeploy: this asserts a LIVE, externally-owned instance,
  not a build-from-HEAD artefact. When delivery updates the instance to new work,
  re-run to confirm it is still current and both actions still hold (the
  green-on-tree-not-live lesson: verify the instance she actually uses).
- Method: `.no-compose` probe-only runner — curls the fixed-address endpoints and
  runs one standard external OTel app against the ingest address; it builds
  nothing.
- Evidence: `evidence/demo_window.json` (discovered demo trace), `app.out` (the
  OTLP export's report), `byid_trace.json` / `byid_logs.json` (the correlated
  round-trip).

## Notes

`.no-compose`. Known caveat for the NEXT goal (the on-screen linked view), found
while verifying this instance and flagged to delivery + the PO: the BUNDLED demo
failed-checkout trace currently has NO cause log attached (the first-party demo
"card declined" log lands with `trace_id` null), so a trace->its-logs view on the
demo trace shows no cause. A standard app's traces DO correlate. For the linked
view's demo to show a cause on the bundled trace, the generator's failure log must
be emitted inside that trace's span.
