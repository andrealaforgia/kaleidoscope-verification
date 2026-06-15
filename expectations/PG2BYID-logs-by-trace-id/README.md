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
  expected 32-hex format, and the raw bad input is not echoed back.

So the correlated logs of one trace are retrievable in one query, scoped to that
trace and no other.

## Source

- Sprint requirement PG-2 criterion 3 (PO, DoD locked). Companion to PG2HEX
  (criterion 5, id-format consistency) — once ids are the same hex string on both
  APIs, this makes the round-trip "trace → its logs" a single query. FIXB1's
  `/help` text is expected to gain the `/api/v1/logs?trace_id=…` curl when this
  lands.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-15 UTC at committed HEAD `d92d3d5`. One query by
  trace_id returns exactly that trace's correlated log(s): by trace A
  (`1fc5fc4f…00d5`) -> only A's log, by trace B (`f7570dac…d9c0`) -> only B's,
  cross-trace exclusion holds; a well-formed non-existent id -> empty 200 (0
  logs); a malformed id -> `400` `{"error":"invalid trace_id: expected a
  32-character hex string"}` (names the format, does not echo the raw input).
  Flipped from RED on the implementer's commit, exactly as pre-authored.
- Previously `broken`: grounded RED 2026-06-15 UTC at committed HEAD `4a8d2d8` —
  the logs query did not honour a `trace_id` filter (a query by trace A returned
  BOTH traces' logs, a non-existent id returned 2, and a malformed id returned
  `200` with logs instead of `400`).
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
