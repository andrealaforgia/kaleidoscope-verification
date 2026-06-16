# Durable always-current demo — acceptance PREP (pre-goal, not yet active)

Pre-goal preparation only. The durable demo-currency fix is queued by the PO for a
later iteration and is in delivery's DESIGN wave (ADR-0079, accepted DESIGN). I
will define the formal observable acceptance WHEN the PO hands it over as a goal;
this note just keeps me ready and records a coherence risk to verify. Nothing here
is pushed to the channel as design feedback.

## What the design promises (observable contract, from ADR-0079)

The demo is synthesised at READ time by a store-free overlay on the router side:
demo records (service.name=kaleidoscope-demo, the demo trace ids 4bf92f… + three
healthy ids, request_count, the "card declined" cause log) are merged into query
results with timestamps `now - offset`; nothing is written to any store. The real
telemetrygen seed is repositioned to `make demo` (real-pipeline path).

So the observable promises are:
- ALWAYS-CURRENT: querying the demo service at any wall-clock time (e.g. a day
  later) returns the demo within a rolling/default window — it never goes empty,
  even on a fresh `make clean` volume.
- NO ACCUMULATION: repeated queries / passage of time never multiply the demo —
  exactly one failed checkout + its single clean cause, three healthy, no
  duplicate or orphaned copies, because nothing is stored.
- REAL DATA UNTOUCHED: a non-demo read returns byte-identical to the inner store
  (the Customer's own telemetry preserved, read-your-write intact).
- STARTUP CURRENCY PROBE: if the synthesised demo would land outside the window
  (clock/offset/window-math bug), the runtime refuses to start (health.startup.refused)
  rather than booting a silently-empty demo.

## Acceptance I'll assert when it becomes a goal (observable)

1. Always-current: with NO fresh seed, the demo service returns its four traces
   (failed checkout + three healthy) within the default window — verified at a
   time well after any fixed-timestamp seed would have aged out; and on a clean
   volume.
2. Coherent story still holds on the synthesised demo: DEMOCAUSE / LINKEDVIEW /
   FINDFAIL all green against it (checkout-shaped Error span + single clean cause,
   error=true returns exactly the failed checkout among the successes, cause off
   the successes).
3. No accumulation: query the demo many times / across a window shift — the demo
   set stays exactly one failed checkout + one cause + three healthy, no growth,
   no orphaned cause copies.
4. Real data untouched: ingest a non-demo trace (on an ephemeral stack) and
   confirm it reads back unchanged with the overlay in place; the overlay adds
   only the demo identity, never alters/duplicates/drops real records.

## COHERENCE RISK to verify (the verifier's specific concern)

The overlay always synthesises the demo for the demo identity, regardless of
whether the SAME demo records are already in the store. Two observable
duplication cases the design does not visibly resolve:

- CUTOVER: the CURRENT managed instance already holds the real telemetrygen demo
  seed (same trace ids 4bf92f… etc.) in its store. Deploying the overlay on top
  would return the demo TWICE (stored real + synthesised) until the old
  fixed-timestamp seed ages out of the window (~a day) — transient duplication
  exactly when a newcomer might open it. Acceptance must check: right after the
  overlay cutover on an instance that previously held a real seed, the demo is NOT
  duplicated (the old seed cleared as part of cutover, or the overlay dedups
  against stored demo-identity records).
- MAKE DEMO COEXISTENCE: running `make demo` on an overlay-enabled stack pushes
  the real seed with the same ids → the demo doubles. Acceptance / docs must make
  clear these are mutually exclusive, or the overlay must dedup.

This is the same duplicate/orphan coherence I caught before (FINDFAIL cause-only,
DEMOCAUSE single-copy), relocated to the synthesis/seed boundary. When this is a
goal, lead with always-current + no-accumulation + these two duplication cases +
the coherent story + real-data pass-through; the Customer's cold run stays the
gate for anything she sees on screen.

## SOURCE-CONFIRMED at slice A (4c070ca) — risk is real at code level

Slice A landed: `crates/kaleidoscope-demo-overlay` (trace half only). NOTE it is
the crate ALONE — NOT yet wired into `kaleidoscope-runtime` (the commit touches no
runtime composition root), so there is NO observable HTTP surface yet; it's library
code with unit tests. Black-box verification waits for the wiring slice. Holding —
not flagging as a defect (premature, partial slice, pre-goal).

The merge is a BLIND MERGE with no dedup against stored demo records
(`crates/kaleidoscope-demo-overlay/src/trace.rs`):
- `get_trace`: `let mut spans = self.inner.get_trace(...)?; spans.push(synthesize_span(...))`
  — appends the synthesised span onto whatever the store already holds for that id.
- `query`: `let mut spans = self.inner.query(...)?; spans.extend(synthesize_all(...).filter(in range))`
  — extends the store's results with all synthesised demo spans.
So if the inner store already contains the real demo seed for those ids (the
CURRENT managed instance does; or after `make demo`), the demo doubles. Steady
state (empty store + overlay) is clean — the unit tests use an empty inner.
WHEN WIRED: verify the cutover on an instance that held a real seed does not double
the demo (seed cleared at cutover, or overlay dedups), plus the always-current /
no-accumulation / coherent-story / pass-through acceptance above.
