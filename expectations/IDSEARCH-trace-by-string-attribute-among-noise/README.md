# IDSEARCH — trace search by a string attribute discriminates one customer out of noise

## Surface

The DATA SUBSTRATE behind iteration 2's identifier path: searching traces on
screen by service + a STRING attribute (customer.id) must return one customer's
traces out of realistic multi-customer noise — bea-test's traces, not everyone's.

Named surface (implementer):
`GET :9092/api/v1/traces?service=&start=&end=&attr_key=<key>&attr_value=<value>`
— returns only traces with at least one span whose attributes contain
`attr_key==attr_value` (the full trace, service+window scope); exact string match;
`attr_key`/`attr_value` are both-or-neither (one alone -> 400); absent both ->
unchanged. STRING attribute only this iteration (numeric type-fidelity deferred).

## Behaviour

Against the shared noisy emitter (`_emitters/noisy_app.py`, service bea-shop, 5
customers: alice/bob/carol/dave/bea-test):

- `?attr_key=customer.id&attr_value=bea-test` -> ONLY bea-test's traces, excluding
  the other four customers;
- `attr_key` alone or `attr_value` alone -> 400 (both-or-neither);
- a returned bea-test trace is her failed checkout (Error), reachable to its
  where->why.

## Verification

- Status: `satisfied` at `0e97db5` on a fresh build.
- Grounded RED first: 2026-06-16 at the prior HEAD — the attr filter was ignored,
  returning ALL five customers' traces (key/value-alone returned 200 not 400).
- Flipped GREEN at `0e97db5`: attr_key=customer.id&attr_value=bea-test returns ONLY
  bea-test's traces (excluding the other four); composed with error=true it narrows
  to her ONE failed checkout, which pivots to WHERE (Error span) + WHY (cause log);
  attr_key-alone or attr_value-alone -> 400 (both-or-neither). Transition-proof.
- Method: `.no-compose`; builds the runtime from the HEAD snapshot, runs it
  overlay-OFF (so the default-on demo overlay injects nothing), drives the noisy
  emitter on a NON-demo service, and exercises the attribute filter + edges.
- Evidence: `evidence/all.json`, `byattr.json`, `key_only.code`, `val_only.code`.

## Notes

`.no-compose`. The companion to LOGSEARCH (symptom path); together they are the
search+discriminate DATA the on-screen Logs/Traces views rest on. The on-screen
search controls and rendered results are client-rendered — proven only by the
Customer's cold browser run; this is "attribute-search data ready", never "the view
is done". The bundled demo also needs the noisy multi-customer set (overlay side).
