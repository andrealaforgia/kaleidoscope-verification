# THRESHOLD — numeric >= attribute filter compares numerically, not lexically

## Surface

Iteration 3, half 2: a numeric `>=` filter on a trace attribute, the data behind
the on-screen numeric threshold search. Over the digit/decimal-boundary spread it
must compare NUMERICALLY.

Named surface (implementer):
`GET :9092/api/v1/traces?service=&start=&end=&attr_key=payment.amount&attr_gte=<number>`
— traces with a span whose `attr_key` has a NUMERIC value `>= attr_gte`, compared
numerically; `attr_key`/`attr_gte` both-or-neither (one alone -> 400); composes with
the existing filters; served same-origin on :9090 (covered by SAMEORIGIN).

## Behaviour

Against the shared numeric emitter (`_emitters/numeric_app.py`, payment.amount over
9, 90, 99.99, 100, 250, 250.50, 500):
- `attr_gte=100` returns exactly the traces at/above 100 — {100, 250, 250.50, 500} —
  and EXCLUDES {9, 90, 99.99}.
- Anti-lexical: 99.99 must be excluded ("99.99" sorts above "100" as strings, 9 > 1);
  9 and 90 excluded (digit-count); 250.50 included and read as 250.5.
- `attr_key` alone or `attr_gte` alone -> 400.

## Verification

- Status: `broken` (RED-grounded; flips GREEN after type fidelity + the filter land).
- Grounded RED: 2026-06-18 at the current HEAD. attr_gte=100 returns 0 traces (the
  numeric filter is not built), and attr_gte alone returns 200 not 400. It depends on
  FIDELITY first — values are strings today, so a numeric comparison cannot be
  genuine. Flips GREEN when attr_gte filters numerically across the boundary.
- Method: `.no-compose`; builds the runtime overlay-OFF, drives the numeric emitter
  (digit/decimal-boundary spread) on a non-demo service, and checks the filter +
  edges, mapping amounts to trace ids from the emitter report.
- Evidence: `evidence/gte100.json`, `report.json`, `key_only.code`, `gte_only.code`.

## Notes

`.no-compose`. Pairs with FIDELITY (the values must be numeric first) — the 99.99 and
the digit-count boundaries are what make this a real numeric test, not a lexical one.
Lands after fidelity (delivery order: FIDELITY -> THRESHOLD -> demo spread). The
on-screen numeric search + the values rendering as numbers are the Customer's cold-run
gate; must also pass SAMEORIGIN (:9090).
