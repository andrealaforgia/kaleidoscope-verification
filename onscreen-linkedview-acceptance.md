# On-screen linked view — acceptance (the Customer's cold-browser done-gate)

This is the acceptance for the on-screen linked trace+logs view, pre-authored in
the Customer's terms while delivery builds it. It is a MANUAL cold-browser
acceptance, deliberately not an automated green: the deliverable is something the
Customer SEES, and only her cold run on the managed instance proves it renders.
The data behind every line below is already verified ready on the data/HTTP
surface (see the expectations named in each item); the rendering is what this
gate adds.

## The done-gate (what the Customer's cold run must confirm)

A newcomer, opening only a browser on the managed instance's address (no
terminal, no prior knowledge of trace ids or query syntax), can:

1. FIND THE FAILURE without being told it exists. From the landing screen there
   is a discoverable way to narrow to failures (an error/"failed" control or
   filter she can see and use), and using it surfaces the failed checkout among
   several successful requests — not a single pre-isolated trace.
   Data verified by: FINDFAIL (multiplicity + non-vacuous error-find +
   discoverable in /help), TRACEERR (the error filter's exclusion semantics).

2. OPEN IT AND READ WHERE IT FAILED. Opening that failed request shows a
   checkout that failed: a span named for the checkout, marked as an error, with
   a readable failure message — not a generic operation with an error bolted on.
   Data verified by: DEMOCAUSE (coherent checkout-shaped failing span).

3. SEE WHY, ON THE SAME SCREEN. On that one screen, with no second tab and no
   copying of an id, she also sees the cause log ("card declined") attached to
   that same trace — the WHERE and the WHY together.
   Data verified by: LINKEDVIEW (the view's one call returns the trace's spans
   and its correlated cause log together), DEMOCAUSE (single clean cause copy, no
   orphans/duplicates).

4. TRUST WHAT SHE SEES. No stray, duplicate, or orphaned records pollute the
   picture: exactly one failed checkout, exactly one cause log on it, the
   successful requests clearly not errors.
   Data verified by: DEMOCAUSE coherence, FINDFAIL distinction.

She then repeats 1–3 with her OWN telemetry (the instance accepts her data), and
the same find -> open -> see-cause-on-one-screen holds for a failure she
generated.

## What does NOT count as passing

- Backend/data green. The data linkage being verified ready is the easy half; it
  is NOT this gate. "Data linkage ready" must never be reported up as "the view
  is done".
- Any run that needs a terminal, a hand-supplied trace id, or foreknowledge of
  the error filter. If she has to already know it exists, the find-by-error is not
  discoverable (the gap the Customer herself caught).
- A demo service holding a single (error) trace. The find-by-error must be
  exercised against real successes, or it distinguishes nothing.
- A green on a polluted instance. This gate is run on the clean managed instance,
  re-seeded once with the multi-trace coherent demo.

## Role boundary

Delivery builds the view and operates the managed instance; the verifier defines
this acceptance and confirms the data surfaces independently, but does NOT build
what is verified, and does NOT stand in for the Customer — her cold run is the
gate. The verifier may run a supporting headless-browser check once the view is
viewable, but that supports, and never replaces, her cold run.

## Status

Pending a viewable screen from delivery. The data items (FINDFAIL, TRACEERR,
DEMOCAUSE, LINKEDVIEW) are tracked as their own expectations; FINDFAIL is red
until the multi-trace seed and the discoverable error-find land. When delivery
reports the view's URL/route, this gate is what the Customer's cold run checks.
