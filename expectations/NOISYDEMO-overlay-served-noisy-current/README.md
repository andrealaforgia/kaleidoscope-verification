# NOISYDEMO — the overlay-served bundled demo is noisy, current, and coherent

## Surface

The bundled demo a newcomer meets on the managed instance, served by the
always-current overlay (ADR-0079, overlay ON, NO stored seed). It must be NOISY
(so finding the failure discriminates rather than reading a sole record), CURRENT
(present at any time without seeding), and COHERENT (exactly one failed checkout
with its single clean cause). This is iteration 2's "noisy bundled demo"
requirement and the durable always-current demo, in one.

## Behaviour (verified GREEN)

Runtime overlay-ON (default), NO seed — the demo is synthesised at read time,
now-relative:

- ALWAYS-CURRENT: a recent window returns the demo with no seeding at all.
- NOISY LOGS: ~12 logs across customers/request types, mostly non-error, EXACTLY
  one ERROR "card declined".
- NOISY TRACES: ~6 traces across >= 3 customers (carrying customer.id), EXACTLY
  one failed checkout.
- SEARCH DISCRIMINATES on the demo: body_regex=(?i)DECLINED (the case-insensitive
  search the Logs view issues) and min_severity=error each return exactly the one
  declined log; attr_key=customer.id&attr_value=<failing customer> returns that
  customer's traces, and composed with error=true narrows to the one failed
  checkout.
- COHERENT PIVOT: with_logs on the failed checkout returns WHERE (Error span) + WHY
  (exactly one cause log), no orphaned/duplicate cause copies.

The failing trace and its customer.id are DISCOVERED from the window, never
hardcoded from the generator's constants.

## Verification

- Status: `satisfied` at the current HEAD (overlay noisy demo, SHA `c96200d`).
- Method: `.no-compose`; builds the runtime from the HEAD snapshot, runs it
  overlay-ON with NO seed, and exercises the demo's noise + discrimination +
  coherence across logs and traces.
- Evidence: `evidence/traces.json`, `logs.json`, `logs_rx.json`, `logs_sev.json`.

## Notes

`.no-compose`. This is what the overlay cutover deploys (overlay-served, never
stales), so the noisy bundled demo and the always-current freshness are the same
thing. The on-screen Logs/Traces search views + pivot that rest on this demo are
client-rendered — proven only by the Customer's cold browser run. Pairs with
LOGSEARCH and IDSEARCH (the search substrates) and DEMOCAUSE/LINKEDVIEW (coherence,
on the seeded side). To be re-confirmed live on the clean instance after the
PO-authorised cutover, before the Customer's cold run.
