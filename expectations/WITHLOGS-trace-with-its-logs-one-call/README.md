# WITHLOGS — a trace with its correlated logs, in one call

## Surface

The combined endpoint behind the on-screen linked view (Surface 2 of 3): one
call returns a trace's spans AND its correlated logs TOGETHER, server-side, so
the view can show them together without the user stitching two panels or copying
a trace id between them.

This verifies the endpoint CONTRACT — the data linkage — only. It is NOT the
on-screen linked view, which is the goal and is proven solely by the Customer's
cold browser run.

## Behaviour

`GET :9092/api/v1/traces/with_logs?trace_id=<32-hex>` returns ONE JSON object
`{ trace_id, spans:[...], logs:[...] }`, scoped to that trace, with NO time
window:

- the response is a single object (not two lists the caller must join), carrying
  the trace's spans AND its correlated logs together;
- every span and every log carries the queried `trace_id` (lowercase hex) — the
  response is scoped to that trace, nothing else leaks in;
- edge: missing `trace_id` -> 400; malformed (not 32 hex) -> 400 with no echo of
  the raw input; unknown 32-hex -> 200 with empty spans AND empty logs.

## Source

- Named by the implementer as the verifiable middle surface of the on-screen
  linked trace+logs view (SHA `83f4d84`). Verified here against a KNOWN-CORRELATED
  trace from the standard external OTel app (a log emitted inside its span) — not
  the bundled demo, whose coherence is a separate track (see DEMOCAUSE). So the
  linkage mechanism is proven independent of demo-data coherence.

## Verification

- Status: `satisfied`.
- Grounded GREEN: 2026-06-14 UTC at committed `83f4d84`, on a fresh clean build:
  the external trace's `with_logs` call returned one object with 2 spans + its
  in-span "checkout failed for customer" log, both carrying that trace id; edges
  all held (missing->400, malformed->400 no-echo, unknown->200 empty).
- Confirmed LIVE on the managed instance with a fresh external trace
  (`4a983474...`): one object `{logs,spans,trace_id}`, 2 spans + 1 correlated
  in-span log, span trace ids all matching, unknown trace -> empty 200. The
  endpoint scopes by trace_id, so it correctly EXCLUDES the orphaned
  (trace_id-null) cause-log copies on the polluted instance — the contract holds
  regardless of that residue (which DEMOCAUSE tracks separately).
- Method: `.no-compose`; builds the runtime from the HEAD snapshot, boots one
  runtime, drives the external app over OTLP/HTTP to produce a correlated trace,
  then queries `with_logs` by the discovered trace id and exercises the edges.
- Evidence: `evidence/trace.txt`, `evidence/with_logs.json`, `evidence/*.code`.

## Notes

`.no-compose`. Surface 2 of the linked-view goal. Surface 1 is the
checkout-shaped failing span (DEMOCAUSE, demo-data track); Surface 3 (the
error-distinguishable find surface) is awaited. None of the three backend
surfaces is the on-screen view: the linked VIEW is "data linkage ready" when they
are green, and DONE only when the Customer opens it cold in a browser and reads
her failed checkout's cause attached to its trace, in one view, with no second
tab.
