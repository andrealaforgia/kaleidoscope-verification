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

VIEWABLE (delivery, 2026-06-15): a "Traces" screen at `http://localhost:9090/traces`
on the clean instance (SHA `21e1596` on the same-origin gateway `4ecaf18`), four-trace
demo preserved. data-testid hooks: nav-traces, trace-service-input,
errors-only-toggle, trace-run-button, trace-row, trace-error-badge, trace-detail,
span-row, span-status-message, log-row, cause-log.

Data items GREEN and confirmed live: DEMOCAUSE, LINKEDVIEW, TRACEERR, FINDFAIL
(incl. the Customer's cause-only-on-failure check). The view's data substrate is
confirmed reachable SAME-ORIGIN on :9090 — errors-only find returns exactly the
failed checkout, filter-off returns all four (only the failed badged Error), and
the failed checkout's WHERE (error message) + WHY (cause log) come together. The
page is served (200, SPA shell + JS bundle).

PASSED (Customer cold run, 2026-06-15) on BUNDLED data — rendering confirmed by
her: the Traces screen in the nav, errors-only find surfacing just the failed
checkout marked ERROR, opening it showing WHERE (the failed POST /checkout span +
its error message) and WHY (the correlated "card declined" cause log) together on
ONE screen, no second tab, one span + one cause, no dupes. So checklist items 1–4
are met for bundled data.

REMAINING: the own-app repeat (item: she repeats find -> open -> see-cause with
her OWN telemetry). Blocked purely on the managed instance being back up.

INCIDENT (2026-06-15): right after the bundled walk the managed instance went
unreachable (all ports refused). Investigated: the runtime did NOT crash —
ExitCode=0, OOMKilled=false, no panic; the logs show an orderly shutdown on a
termination signal (shutdown_initiated -> drained -> shutdown_complete exit 0),
and RestartPolicy=no so it stayed down. Open with delivery: what sent the signal
during a normal walk, and why the always-current instance didn't auto-recover.
Delivery to restart + confirm live; verifier to re-confirm clean before the
own-app repeat.

NON-BLOCKING UX follow-up: the default ~1h time range shows only the failed trace
(the three successes are timestamped outside it); she had to widen to 24h to see
the failure among the successes. errors-only works regardless. Flagged to delivery
to seed the successes within the default window. Not blocking the close.

(No Playwright/headless browser in the verifier environment; the Customer's cold
run is the human gate, now passed for bundled data; delivery is adding their own
Playwright e2e as a separate programmatic proof.)
