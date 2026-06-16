# Iteration 2, IDENTIFIER path — acceptance (trace search by service + string attribute)

The second of the frozen two-path scope (fast-follow after the symptom path):
investigate-from-an-identifier on screen — find a trace by a known attribute value
without a trace id, then read its correlated where->why.

## Done-gate — the Customer's cold browser run (her own telemetry)

Starting from only customer.id=bea-test and a time, NEVER typing a trace id: she
searches traces on screen by service + that attribute, finds bea-test's failing
trace among realistic noise, and reads its logs / WHERE + WHY on screen.

## What the Customer does (observable, her terms)

1. Open the Traces search on screen over a time window.
2. Search by service AND by a string attribute customer.id=bea-test — no trace id.
3. Among realistic noise (several customers, several request types), the search
   returns bea-test's traces and NOT everyone's.
4. Open her failing trace and read its logs / WHERE + WHY (the existing correlated
   view, reached from the attribute search).

## What the verifier confirms (data substrate; ephemeral/isolated stacks, read-only on live)

- ATTRIBUTE SEARCH EXISTS: traces query supports a STRING attribute filter
  (customer.id) alongside service + window. STRING only this iteration; numeric
  filtering stays deferred with the type-fidelity fix.
- DISCRIMINATION: against the noisy mix (5 customers x several request types from
  the shared emitter), customer.id=bea-test returns ONLY bea-test's traces — not
  alice/bob/carol/dave's, not everything, not right only because it is the sole
  record. The same anti-gimme discipline as the symptom path and FINDFAIL.
- CORRELATION REACHED: a returned bea-test trace resolves to its where->why
  (its spans + its logs together) — reusing the linked view, reached from the
  attribute search rather than a typed id.
- NOISY BUNDLED DEMO: the same noisy log+trace seed (several customers) backs the
  bundled demo so a newcomer's cold run discriminates, not finds a sole record.

## On-screen (the gate, NOT the verifier's to claim)

The Traces search controls and the rendered results/correlated view are
client-rendered — proven only by her cold browser run; delivery's Playwright e2e
on an ISOLATED/ephemeral stack is the programmatic backup. The data substrate is
"attribute-search + correlation data ready", never "the view is done".

## Genuine ambiguities flagged (proposed defaults; confirm before build)

1. String-attribute match — assumed EXACT match on the attribute value
   (customer.id=bea-test matches exactly "bea-test", not a substring), so it does
   not also catch "bea-test-2". Confirm exact vs prefix/substring.
2. Attribute location — assumed the filter matches a SPAN attribute (customer.id
   is set on the span by the app). If it should also match resource attributes,
   say so; the emitter sets customer.id as a span attribute.
3. Combine semantics — assumed service AND attribute are ANDed (both must hold).
   Confirm.

Shared with the symptom path: the same noisy emitter (`_emitters/noisy_app.py`)
drives both; her cold runs are the gate for both; the on-screen render is never
claimed from the data substrate.
