# FINDFAIL — find the failure by its error state: real, non-vacuous, discoverable

## Surface

Part of the on-screen linked-view Definition of Done: a newcomer must be able to
FIND the failed checkout by its error state, on the demo data the Customer and the
view use. Customer-caught gap (2026-06-15): a demo service holding a single
(error) trace makes "filter to errors" vacuous — any query returns it — and the
documented help advertised only service+window, so the error-find was not
discoverable at all.

## Behaviour

Against the first-party demo seed, in the observable service+window
(`service=kaleidoscope-demo`):

- MULTIPLICITY: the demo holds SEVERAL successful traces PLUS exactly one failed
  checkout (a checkout-shaped Error trace) — not a single trace;
- NON-VACUOUS DISTINCTION: filtering that service+window to errors
  (`error=true`) returns EXACTLY the failed checkout, excluding every successful
  trace;
- DISCOVERABLE: the product's own `GET /help` advertises the error-find (a
  runnable traces example carrying `error=true`), so a newcomer learns it exists
  without already knowing it.

## Source

- The Customer accepted the terminal cold walks, then caught that the managed
  demo's error-find was vacuous (single trace) and undiscoverable (help listed
  service+window only). The PO folded this into the on-screen-view acceptance:
  the find-by-error must be real and discoverable, exercised against multiple
  traces. My own earlier "confirmed live" error-find claim was vacuous on that
  single-trace instance; this expectation corrects and strengthens it.

## Verification

- Status: `broken` (RED-grounded; flips GREEN when delivered).
- Grounded RED: 2026-06-15 UTC at committed `0052cf9`, on a fresh clean build.
  The demo holds 0 successful traces + 1 failed, so find-by-error is vacuous; and
  `/help` lists service+window only, with no error filter to discover. Flips GREEN
  when the demo seed carries several successful traces plus the failed checkout
  AND `/help` advertises the error-find.
- Companion to TRACEERR: TRACEERR proves the error filter's exclusion SEMANTICS on
  a multi-trace build; FINDFAIL proves those semantics are NON-VACUOUS and
  DISCOVERABLE on the actual demo the Customer and the view use.
- Method: `.no-compose`; builds runtime + first-party generator from the HEAD
  snapshot, seeds the demo, then checks trace multiplicity, the error filter
  result, and the `/help` text.
- Evidence: `evidence/all_traces.json`, `evidence/err_traces.json`,
  `evidence/help.txt`.

## Notes

`.no-compose`. The find-by-error half of the on-screen-view DoD. Even once green,
the on-screen rendering (find the failure on screen, open it, see its spans and
attached cause log in one view) is proven only by the Customer's cold browser run.
