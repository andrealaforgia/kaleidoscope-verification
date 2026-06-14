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

- Status: `broken` (transition-proof; RED until the fix commits).
- Grounded RED: 2026-06-14 UTC at committed HEAD `3658376` (generator `4eacfb8`).
  After the generator, `:9091` returns **217 records**: 1 application log, the
  rest transport noise (sample bodies `poll_ready; idle`, `poll_ready;
  connecting`, `poll_ready; not ready`). Flips GREEN when only the application
  log remains (zero noise, count 1).
- Method: build runtime + generator from the HEAD snapshot, run the generator
  against the runtime, query the UNFILTERED `:9091 /api/v1/logs`, and check the
  application log is present, no body matches a transport-noise pattern, and the
  total is exactly 1.

## Notes

`.no-compose`. Now gradeable because the generator is committed (the noise rides
in via the generator's transport client). The `count==1` secondary backstops any
noise pattern the body regex might miss. Companion to CRGEN03, whose `acme` log
count (217) first surfaced this.
