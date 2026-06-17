# Iteration 3 — numeric attribute fidelity + numeric threshold search (traces)

Correctness-first. TRACE attributes only this iteration (logs/metrics typing
deferred). The done-gate is the Customer's cold browser run on her noisy numeric mix.

## Done-gate (Customer cold run, her own noisy mix)

Checkouts carry payment.amount across a digit-boundary spread (9, 90, 100, 250,
and a couple more) as REAL NUMERIC attributes; on the Traces screen,
payment.amount >= 100 returns exactly {100, 250, ...} and EXCLUDES {9, 90}, and
the values render as numbers (250, not "250").

## Two observable parts

1. TYPE FIDELITY: a numeric attribute the app emits as a number comes back as a
   number, not a string. Observable: emit payment.amount = 250 (a number),
   retrieve the trace, the value reads as 250 (a JSON number), not "250".
   GROUNDED RED (2026-06-17): the platform currently COERCES numeric attribute
   values to strings — I emitted 9/90/100/250/1500 as ints and all came back as
   strings. (Expectation FIDELITY, RED.)
2. NUMERIC THRESHOLD SEARCH on the Traces screen: filter by a numeric attribute
   with a SINGLE comparison (payment.amount >= a threshold), returning exactly the
   traces at/above it and excluding the cheaper ones.

## The correctness discriminator (non-negotiable)

The comparison must be NUMERIC, not a lexical string sort. A string sort ranks "9"
and "90" ABOVE "100"/"250", so the digit-boundary spread is the real test: verify
SPECIFICALLY that 9 and 90 are EXCLUDED by >=100 while 100 and 250 are INCLUDED.
That working across the boundary IS the proof the value is numeric end to end
(ingest -> query -> screen), not display-only. A green that only uses an
all-same-digit-count spread (e.g. 100/200/300) would be a blind spot and must NOT
be accepted.

## What the verifier confirms (data substrate; ephemeral/isolated, read-only on live)

- FIDELITY (RED-grounded): payment.amount emitted numeric comes back a JSON number,
  not a string — across the digit-boundary spread.
- THRESHOLD (to RED-ground when delivery names the surface): on the traces query,
  the numeric >= filter returns exactly the traces at/above the threshold and
  excludes the cheaper ones, ACROSS THE DIGIT BOUNDARY (>=100 -> {100,250,1500},
  excludes {9,90}). Driven by the shared numeric emitter (_emitters/numeric_app.py).
- DEMO: the bundled (overlay) demo carries a numeric-amount spread across the digit
  boundary, so a newcomer's cold run discriminates rather than hitting a gimme.

The on-screen rendering (values shown as numbers, the threshold control, the
filtered list) is client — proven by her cold run; delivery's e2e on an isolated
stack is the programmatic backup. And per the served-view lesson, the threshold
filter must also be exercised on the VIEW's own origin (:9090), not only the
signal port — i.e. SAMEORIGIN-style, so the numeric search isn't a backend-only green.

## Genuine ambiguities to flag before building

1. Threshold query surface — delivery to name the route + exact param/syntax for
   the numeric >= comparison (e.g. an attr_key + a numeric-gte param). I won't
   guess the param (a guessed RED is a false RED); I RED-ground THRESHOLD when named.
2. Integer vs float — the spread is integers (9..1500). Is float fidelity in scope
   (payment.amount = 250.50 -> 250.5), or integers only this iteration? Affects the
   emitter and the fidelity assertion.
3. Operator — ">=" only (single threshold; other operators explicitly out of
   scope). Confirm it's >= (at/above), inclusive of the threshold value itself
   (100 included).

Out of scope (deferred): numeric typing on logs/metrics attributes; multi-condition
queries; operators beyond the single threshold; attribute-search-on-logs; combined
text+severity.
