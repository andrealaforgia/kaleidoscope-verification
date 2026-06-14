# FIXA — demo-logs-no-transport-noise

## Surface

Sprint item FIX-A (the demo pollutes its own logs with transport noise). The
observable `:9091 /api/v1/logs` set after the generator runs.

## Behaviour

After the first-party generator runs against the runtime, the unfiltered logs
query returns ONLY the demo's application log(s), with zero transport noise:

- the application log `checkout failed: card declined` is present;
- ZERO records are transport noise (no body like `poll_ready` / `encoding
  SETTINGS` / h2 / hyper / tonic / tower / rustls chatter);
- secondary, deterministic: the total log count is exactly 1.

## Source

- Sprint requirement FIX-A (PO, agreed with Customer). PO gate: robust
  (no transport noise, application log preserved) is primary; `count==1` is a
  deterministic secondary. The Customer re-counts by hand, so the number must
  hold black-box.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `66568d0` (FIX-A). After the
  generator, `:9091` returns exactly **1 record** — the application log
  `checkout failed: card declined` — with zero transport-noise records. Flipped
  from RED on the implementer's commit (robust gate + the deterministic
  `count==1`), exactly as the transition-proof expectation was pre-authored.
- Previously `broken`: grounded RED 2026-06-14 at HEAD `3658376` — `:9091`
  returned 217 records (1 application log + transport noise like `poll_ready;
  idle`).
- Method: build runtime + generator from the HEAD snapshot, run the generator
  against the runtime, query the UNFILTERED `:9091 /api/v1/logs`, and check the
  application log is present, no body matches a transport-noise pattern, and the
  total is exactly 1.

## Notes

`.no-compose`. Now gradeable because the generator is committed (the noise rides
in via the generator's transport client). The `count==1` secondary backstops any
noise pattern the body regex might miss. Companion to CRGEN03, whose `acme` log
count (217) first surfaced this.
