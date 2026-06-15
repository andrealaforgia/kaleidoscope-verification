# PG2EXT — logs-by-trace-id-external-sdk (PG-2 external binding)

## Surface

Product goal PG-2 (log↔trace correlation): the "retrieve a trace's logs in one
query by its id" capability must hold for a STANDARD external OpenTelemetry SDK,
not only the first-party generator. This closes the external-binding criterion by
composing the PG-1 external app with the by-trace_id logs query.

## Behaviour

The PG-1 external Python app (official `opentelemetry-sdk` only, zero
Kaleidoscope code, a log emitted INSIDE its active span, exported over the real
OTLP/HTTP wire) reports its own trace id. Then a single query
`GET :9091/api/v1/logs?trace_id=<the app's own trace id>` returns that app's
in-span log, carrying exactly the app's trace id, and no other trace's logs. So a
human using a normal external SDK can pull a trace's correlated logs in one query
by id.

## Source

- PG-2 DoD external-binding criterion (PO). Builds on PG2BYID (the by-trace_id
  route + scoping/validation) and PG2HEX (id-string consistency), proving the
  same one-query retrieval from a standard external SDK rather than the
  first-party generator. Distinct from PG1 (which proves the trace round-trips)
  and from PG2BYID (first-party two-trace scoping).

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-15 UTC at committed HEAD `1a88b3d`. The external app
  exported trace `d16733b1…6f03`; one query by that id on `:9091` returned the
  app's in-span log ("checkout failed for customer bea-test"), scoped to that
  trace only.
- Regression net (GREEN-on-arrival): RED if the external app's trace does not
  round-trip its logs by id — the by-id query returns nothing, returns the wrong
  trace, or the external SDK's trace id is not honoured.
- Method: `harness/run-kaleidoscope-runtime.sh` snapshot build of the runtime;
  boot one runtime, run the external OTel app in a `python:3-slim` container over
  OTLP/HTTP, take the app's reported trace id, and query `:9091` by that id.
- Evidence: `evidence/trace.txt` (the external trace id), `evidence/by_ext.json`
  (the one-query result), `evidence/app.out` (the app's report).

## Notes

`.no-compose`: PG2EXT manages its own runtime + external-app containers. Reuses
PG1's `pg1_app.py` unchanged (a standard SDK, app-generated trace id), so this is
a cross-compat oracle: the retrieval works for arbitrary external producers, not
just the internal generator's fixed-id demo.
