# PG2BYID — logs-by-trace-id (PG-2 criterion 3)

## Surface

Product goal PG-2 (log↔trace correlation), criterion 3: given a trace_id, a
single query returns that trace's correlated log(s) — the operator does not have
to pull a window and filter by eye.

## Behaviour

The PG-1 external OTel app (a log emitted INSIDE its active span) is run twice,
producing two distinct traces A and B, each with its own in-span log (identical
body, different trace_id). Then, from `:9091 /api/v1/logs`:

- a single query filtered by trace_id A returns at least one log, EVERY returned
  log carries trace_id A, and NONE carries trace_id B (filters A in, excludes B);
- the symmetric control: a query by trace_id B returns exactly trace B's log(s)
  and excludes A;
- a query by a non-existent (well-formed) trace_id returns zero logs (empty 200);
- a malformed trace_id (not a 32-hex id) returns `400`, the error names the
  expected 32-hex format, and the raw bad input is not echoed back;
- a query by trace_id A WITHOUT a time window returns trace A's log(s) — a unique
  trace id alone suffices, with no mandatory `start`/`end`, the same way the
  `:9092 /api/v1/traces/by_id` route needs no window. This is the customer's
  "one query by id".

So the correlated logs of one trace are retrievable in one query, scoped to that
trace and no other, by the id alone.

## Source

- Sprint requirement PG-2 criterion 3 (PO, DoD locked). Companion to PG2HEX
  (criterion 5, id-format consistency) — once ids are the same hex string on both
  APIs, this makes the round-trip "trace → its logs" a single query. FIXB1's
  `/help` text is expected to gain the `/api/v1/logs?trace_id=…` curl when this
  lands.

## Verification

- Status: `broken` (strengthened — the no-window case the customer actually needs
  is not yet satisfied).
- Grounded RED: 2026-06-15 UTC at committed HEAD `1ed6381`. The windowed scoping
  works, but a query by trace_id A **without** a time window returns `400 "Failed
  to deserialize query string: missing field 'start'"` — the logs-by-trace_id
  query still DEMANDS a `start`/`end` window. A unique trace id alone must return
  its logs (the `:9092 traces/by_id` route needs no window); requiring a window
  is exactly the Customer's blocker ("the logs query insists on a time window").
  Flips GREEN when a trace_id alone returns that trace's log(s).
- Partial GREEN (windowed scoping only) was grounded 2026-06-15 at HEAD `d92d3d5`:
  with `start`/`end` supplied, by trace A (`1fc5fc4f…00d5`) -> only A's log, by
  trace B (`f7570dac…d9c0`) -> only B's, non-existent id -> empty 200, malformed
  id -> `400` naming the 32-hex format. That earlier pass covered ONLY the
  windowed case; it always supplied `start`/`end`, so it never exercised the
  trace_id-alone path — my blind spot, surfaced by the Customer's real use.
- Previously `broken`: grounded RED 2026-06-15 UTC at committed HEAD `4a8d2d8` —
  the logs query did not honour a `trace_id` filter at all (a query by trace A
  returned BOTH traces' logs, a non-existent id returned 2, malformed -> `200`).
- Method: `harness/run-kaleidoscope-runtime.sh` builds the runtime from the HEAD
  snapshot; the runner boots one runtime, runs the external OTel app twice (two
  traces, two in-span logs), then queries `:9091` by trace_id A, by trace_id B,
  and by a bogus id, asserting per-trace scoping and cross-trace exclusion.
- Evidence: `evidence/traces.txt` (the two emitted trace ids), `evidence/by_a.json`
  / `by_b.json` (the scoped queries), `evidence/by_bogus.json`,
  `evidence/unfiltered.json` (both logs present pre-filter).

## Notes

`.no-compose`: PG2BYID manages its own runtime + external-app containers.
Generator-independent. The exact query form probed is `/api/v1/logs?trace_id=<32-hex>`
(the PO-stated form); the contract under test is observable — one query, scoped
to one trace — not the route's internals.
