# HELPRUN — help-examples-return-data

## Surface

The getting-started help must be usable COLD. A newcomer who knows nothing about
the system opens `GET /help` on a running, demo-seeded stack, copies each printed
example exactly as written, and gets back real data for every signal. This is the
PO's re-opened Definition of Done, strengthening the earlier "the help text
exists" check (see FIXB1) to "each example, followed verbatim, returns that
signal's data".

## Behaviour

With the demo data seeded (all three signals present), starting only from the
text of `GET /help`:

- the metrics example, copied verbatim, returns metric data;
- the logs example, copied verbatim, returns log data;
- the traces-over-a-service-window example, copied verbatim, returns trace data;
- the single-trace-by-id example, copied verbatim, returns the trace's spans;
- no example returns a success-looking HTML page (a 200 that renders the
  dashboard instead of answering with the signal's data).

Each example is run truly verbatim: the runner executes the example's own
`http://localhost:<port>/...` address from inside the runtime's network
namespace, so the exact host/port/path the help prints is what gets called —
nothing is rewritten. This mirrors a newcomer's "the stack is on my localhost".

## Source

- PO re-opened the discoverable-help capability after the Customer followed it
  cold from outside: the help text and examples are clear, but the logs, traces,
  and by-id examples all point at the metrics address while logs and traces
  answer elsewhere, so verbatim they return no data. The PO asked to strengthen
  the acceptance from "the help text exists" to "each example, followed verbatim,
  returns that signal's data", and folded in that the example values/time should
  match the demo so the first cold run returns data.

## Verification

- Status: `broken` (transition-proof; RED until the help examples are usable cold).
- Grounded RED: 2026-06-15 UTC at committed HEAD `4a8d2d8`, demo seeded via the
  first-party generator. The four printed examples all address `localhost:9090`
  with placeholder values and a fixed past window. Observed verbatim:
  - metrics example -> HTTP 200 but **0 series** (its `process_cpu_utilization`
    metric and `2026-06-14` window don't match the demo data);
  - logs / traces / by-id examples -> **HTTP 404** (they hit the metrics address,
    which has no such route in this runtime). On a stack that serves the
    dashboard, those same wrong-address calls instead return the dashboard **HTML
    page with 200** — the "success-looking dead end" the Customer hit. Either way
    the newcomer gets no data.
  Flips GREEN when every printed example, run verbatim against the seeded demo,
  returns its signal's data as JSON.
- Method: `harness/run-kaleidoscope-runtime.sh` snapshot build of the runtime +
  first-party generator; boot one runtime, seed all three signals, `GET /help`,
  extract each example URL from the help text, run each verbatim inside the
  runtime's netns, and assert each returns that signal's data (JSON, non-empty,
  not HTML).
- Evidence: `evidence/help.txt` (the help as served), `evidence/urls.txt` (the
  extracted examples), `evidence/ex_metrics.out` / `ex_logs.out` /
  `ex_traces.out` / `ex_byid.out` (each verbatim run's status, content-type, and
  body).

## Notes

`.no-compose`: HELPRUN manages its own runtime + generator + example-runner
containers. Strengthens and supersedes FIXB1's text-only check. Non-blocking
nicety folded into the teeth: because the examples are run verbatim against the
demo seed, the example values and time window must reference the demo's real
data for the run to return anything — which is exactly the cold-start the
Customer needs.
