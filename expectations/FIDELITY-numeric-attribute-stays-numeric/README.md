# FIDELITY — a numeric attribute stays numeric end to end

## Surface

Iteration 3, half 1 (correctness): a numeric attribute the app emits as a NUMBER
must come back as a NUMBER, not a string. This is the foundation the numeric
threshold search rests on — a `>=` comparison can only be genuinely numeric (not a
lexical string sort, where "9" outranks "100") if the value is a number end to end:
ingest -> store -> query -> JSON.

## Behaviour

The shared numeric emitter (`_emitters/numeric_app.py`) emits checkouts with
payment.amount across a digit-boundary spread (9, 90, 100, 250, 1500) as a NUMERIC
(int) OTel attribute. On retrieval, each payment.amount value must be a JSON number
(not a string).

## Verification

- Status: `broken` (RED-grounded; flips GREEN with the type-fidelity fix).
- Grounded RED: 2026-06-17 at the current HEAD on a fresh build. payment.amount
  emitted as ints 9/90/100/250/1500 all come back as STRINGS ("9".."1500") — the
  platform coerces numeric attribute values to strings. Flips GREEN when they come
  back as JSON numbers.
- Method: `.no-compose`; builds the runtime from the HEAD snapshot, overlay-OFF,
  drives the numeric emitter on a non-demo service, and checks the JSON type of
  payment.amount.
- Evidence: `evidence/traces.json`, `evidence/num.out`.

## Notes

`.no-compose`. Half 1 of iteration 3; pairs with THRESHOLD (the numeric >= search,
to be RED-grounded once delivery names the query surface) — the digit-boundary
spread is what makes THRESHOLD a real numeric test rather than a lexical one. The
on-screen rendering of values as numbers is the Customer's cold-run gate.
