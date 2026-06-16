# Iteration 2, SYMPTOM path — acceptance (Logs view + pivot)

Investigate-from-a-symptom on screen: a Logs view to search logs in their own
right (no trace in hand), then pivot from a found log into the existing correlated
where->why view. Frozen scope is two-path (symptom + identifier); this is the
symptom path, built first.

## Done-gate — the Customer's cold browser run (her own telemetry)

Starting from only the symptom "declined" and a time, NEVER typing a trace id:
she opens the Logs view, searches, finds the one declined log among realistic
noise, pivots to its trace, and reads the cause (WHERE + WHY) on screen.

## What the Customer does (observable, her terms)

1. Open the Logs view cold from the dashboard (a nav entry next to Metrics/Traces).
2. Search logs over a time window by severity and/or text-in-body ("declined"),
   with no trace in hand.
3. Among realistic noise (many logs, several customers and request types, mostly
   successful), the search surfaces the ONE declined log — not everything, and not
   right only because it is the sole record.
4. Read the matching log record(s) on screen.
5. Pivot from the found declined log into the correlated where->why view (its
   trace's spans + its logs together).
6. Read WHERE (the failing checkout span + its message) and WHY (the cause) on
   screen.

## What the verifier confirms (data substrate; ephemeral/isolated stacks, read-only on live)

- SEARCH EXISTS: the logs query supports search by severity AND by text-in-body
  over a time window (today it supports only window + trace_id — net-new).
- DISCRIMINATION (the real test, not a gimme): against a noisy log set — many logs
  across several customers and request types, mostly non-error, EXACTLY one
  "declined" — a text search "declined" returns exactly that one log, and a
  severity=error search returns the error log(s), each excluding the mass of
  non-error/non-matching logs. Returning everything, or being right only because
  it is the sole record, FAILS (same discipline as FINDFAIL for traces).
- PIVOT DATA: the found declined log carries its trace_id, so the pivot needs no
  typed id; that trace_id resolves to the correlated where->why (the failing
  checkout span + message AND the cause log together — reuses LINKEDVIEW, reached
  from the log).
- NOISY BUNDLED DEMO: the bundled demo on the managed instance carries a noisy log
  set with the same shape, so a newcomer's cold run discriminates a real failure
  out of noise rather than finding a single planted log.

## On-screen (the gate, NOT the verifier's to claim)

The Logs view rendering, the search controls, the pivot click, and reading
WHERE+WHY on screen are client-rendered — proven only by her cold browser run.
Delivery's Playwright e2e on an ISOLATED/ephemeral stack (never the managed
instance) is the programmatic backup. The data substrate above is "search + pivot
data ready", never "the view is done".

## Ambiguities — RESOLVED by the PO (2026-06-16)

1. Text match — CASE-INSENSITIVE from the user's point of view: typing "declined"
   OR "Declined" both find "checkout failed: card declined". IMPORTANT: the backend
   `body_contains` is CASE-SENSITIVE (verified — "Declined" -> 0, LOGSEARCH). So the
   ON-SCREEN search box MUST normalise case (client lowercase or equivalent) so a
   case mismatch does NOT silently return empty — that empty-looks-like-worked trap
   is explicitly in scope to avoid. Acceptance: in her cold run, "Declined" (capital)
   finds the declined log. If case-insensitive proves non-trivial, flag it — it
   becomes a fast-follow, but the target is case-insensitive.
2. Severity — "this level or higher" floor; the declined cause is ERROR, so
   severity=error discriminates. Accepted.
3. Combined text+severity — NOT this iteration: text-alone OR severity-alone each
   suffices for her run. Do not build the combined "errors containing declined"
   query (deferred to broader filter ergonomics).
4. Demo noise floor — accepted: about a dozen logs across >= 3 customers and >= 2
   request types, mostly non-error, EXACTLY one "declined" (the noisy emitter
   already meets this).

Pre-cold-run: the bundled demo must be RE-SEEDED fresh with the noisy log set
before her symptom-path cold run (the managed demo has aged out). Tell the PO when
the view is live AND freshly seeded; her cold run is the gate.

## Then (identifier path, fast-follow this iteration)

Traces search on screen by service + a STRING attribute (customer.id=bea-test),
discriminating against the same noise; from the found trace, read its logs /
WHERE+WHY. Separate acceptance to follow; string attribute only (numeric stays
deferred with the type-fidelity fix).
