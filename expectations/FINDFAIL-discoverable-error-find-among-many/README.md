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
  without already knowing it;
- CAUSE ONLY ON THE FAILURE (Customer-checked): the "card declined" cause log is
  attached to the failed checkout and to NO successful trace — the successful
  checkout (same operation, Ok) carries zero cause logs, so the cause does not
  bleed onto a success.

## Source

- The Customer accepted the terminal cold walks, then caught that the managed
  demo's error-find was vacuous (single trace) and undiscoverable (help listed
  service+window only). The PO folded this into the on-screen-view acceptance:
  the find-by-error must be real and discoverable, exercised against multiple
  traces. My own earlier "confirmed live" error-find claim was vacuous on that
  single-trace instance; this expectation corrects and strengthens it.

## Verification

- Status: `satisfied` on a fresh clean build at `4a647ad`, AND independently
  confirmed LIVE on the re-seeded clean managed instance (2026-06-15).
- Grounded RED first: 2026-06-15 UTC at committed `0052cf9`, on a fresh clean
  build. The demo held 0 successful traces + 1 failed (find-by-error vacuous) and
  `/help` listed service+window only (no discoverable error filter).
- Flipped GREEN: at `4a647ad` (seed `af31955` + help `4a647ad`). Build: the demo
  holds 3 successful traces + exactly 1 failed checkout; `error=true` returns
  EXACTLY the failed checkout, excluding all successes; `/help` advertises a
  runnable "find failed traces" error=true example. LIVE re-confirmation on the
  re-seeded clean instance (traces discovered from the window, not trusted by id):
  4 demo traces — 3 healthy (checkout Ok, products Ok, cart Ok) + 1 failed
  checkout; `error=true` returns exactly the failed one; `/help` advertises the
  error-find; the failed checkout's coherence is unchanged (one checkout-shaped
  Error span + its one clean "card declined" cause log).
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
