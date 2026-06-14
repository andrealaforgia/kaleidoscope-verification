# PG2HEX — logs-trace-id-hex (PG-2 criterion 5)

## Surface

Product goal PG-2 (log↔trace correlation), criterion 5: the logs query API
exposes the trace and span identifiers in the same shape as the traces API, so a
human and a query can correlate a log to its trace by the same id string.

## Behaviour

After an external OTel app emits a log INSIDE an active span (the PG-1 app),
the log retrieved from `:9091 /api/v1/logs` exposes:

- `trace_id` as a 32-char lowercase hex string, and
- `span_id` as a 16-char lowercase hex string,

in the same shape the traces API (`:9092`) already uses. The log's `trace_id`
string equals the same trace's `trace_id` string from `:9092` (byte-for-byte the
same characters), and its `span_id` matches a span id in that trace.

## Source

- The trace_id-shape mismatch surfaced black-box by the PG1 bonus (the logs API
  returned integer byte arrays while the traces API returned hex). PO accepted it
  as PG-2 criterion 5.

## Verification

- Status: `broken` (transition-proof; RED until the fix commits).
- Grounded RED: 2026-06-14 UTC at committed HEAD `af00199`. The logs API returns
  `trace_id` as a byte array (e.g. `[21,180,212,…]`) and `span_id` as
  `[201,34,…]` — not hex strings. Flips GREEN when both are lowercase-hex strings
  matching the traces API and equal to the same trace's ids.
- Method: reuses the PG-1 external OTel app (a log emitted inside the span);
  builds the runtime from the HEAD snapshot, runs the app, queries `:9091` logs
  and `:9092` traces, and asserts the hex shape + cross-API id-string equality.

## Notes

`.no-compose`. This is PG-2's serialisation-shape slice only; the separate
"retrieve a trace's logs in one query by trace_id" capability
(`/api/v1/logs?trace_id=…`) is a distinct expectation to be authored when that
route lands.
