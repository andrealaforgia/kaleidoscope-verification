# Iteration 3 — numeric attribute fidelity + numeric threshold search (traces)

Correctness-first. TRACE attributes only this iteration (logs/metrics typing
deferred). The done-gate is the Customer's cold browser run on her noisy numeric mix.

## Done-gate (Customer cold run, her own noisy mix) — FINALISED 2026-06-18

Checkouts carry payment.amount across the spread 9, 90, 99.99, 100, 250, 250.50,
500 as REAL NUMERIC attributes (INTS and FLOATS). On the Traces screen,
payment.amount >= 100 returns exactly {100, 250, 250.50, 500} and EXCLUDES
{9, 90, 99.99}, and the values render as numbers (250, and 250.50 as 250.5),
not strings.

## Resolved (PO + Customer, 2026-06-18)

- Operator: ">=", INCLUSIVE — the threshold value is included (>=100 returns 100).
- Floats: IN SCOPE — payment.amount is money; 250.50 -> 250.5 (a number), not
  "250.50"; integer-only would re-open next week.
- Threshold query route/param: delivery's to name (THRESHOLD RED-grounds when named).

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

The comparison must be NUMERIC, not a lexical string sort. Two anti-lexical
boundaries, both held hard:
- DIGIT-COUNT: "9" and "90" sort ABOVE "100" as strings, so >=100 must EXCLUDE
  9 and 90.
- DECIMAL (the Customer's sharper probe): "99.99" sorts ABOVE "100" too (9 > 1),
  so a string-comparison bug would wrongly INCLUDE 99.99 in >=100. Numeric must
  EXCLUDE 99.99. And 250.50 must be INCLUDED and read as 250.5.
Verify SPECIFICALLY that {9, 90, 99.99} are excluded by >=100 and {100, 250,
250.50, 500} included. That, across both boundaries on ints AND floats, IS the
proof the value is genuinely numeric end to end (ingest -> query -> screen), not
display-only. A green WITHOUT 99.99 (or using an all-same-digit spread) is a blind
spot and must NOT be accepted.

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
