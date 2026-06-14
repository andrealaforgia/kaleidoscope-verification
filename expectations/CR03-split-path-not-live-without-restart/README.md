# CR03 — split-path-not-live-without-restart (regression negative control)

## Surface

The split deployment (separate `kaleidoscope-gateway` + separate `query-api`),
as the negative control for consolidated-runtime-v0 / ADR-0076. Operator-facing.

## Behaviour

This is the negative control the implementer asked for (msg 037): it proves the
split path is **not** live, so the consolidation fix (CR01/CR02 — live with no
restart) is demonstrably real, not vacuous.

Same Pulse pillar root throughout:

1. a `query-api` boots over a fresh empty root and stays RUNNING; `gen` → 0
   series (empty, as expected).
2. a `gateway` boots over the SAME root, ingests one `gen` metric, then is
   SIGTERM'd to flush Pulse to disk (the record is now durably on disk).
3. the STILL-RUNNING `query-api` is queried → **0 series**: it loaded the store
   at boot and does not see the post-boot write. This is the regression.
4. a FRESH `query-api` over the same root (a restart) → **1 series**: the record
   is on disk, visible only after a reload.

So the split path requires a restart to see new telemetry — exactly the failure
the consolidated runtime removes by sharing one live `Arc` store between ingest
and query.

## Source

- The regression characterised in `docs/roadmap/consolidation-roadmap.md` and
  ADR-0076 (separate processes whose file-backed stores load once at startup).
- Contract anchor: implementer msg 037's "THE REGRESSION IT FIXES (negative
  control you can run)". Differential partner of CR01/CR02.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at HEAD `db044bf`. `running_empty=0`,
  `running_after_ingest=0` (the already-running query-api is blind to the
  post-boot ingest), `restarted=1` (durable, visible only after a reload).
- Transition-proof / adversarial: RED if the already-running query-api returns
  ≥1 at step 3 — that would mean the split path is live too and the
  consolidation differential is weaker than the feature claims (a reportable
  finding). It returned 0, so the regression reproduces.
- Method: `harness/run-eg.sh` builds the gateway + query-api images; the runner
  boots a running query-api over a fresh root, ingests via a separate gateway
  into the same root with a SIGTERM flush, queries the running query-api, then
  boots a fresh query-api over the same root and queries again.

## Notes

`.no-compose`: CR03 manages its own gateway + query-api containers. Read this
beside CR01/CR02: split path needs a restart (0 → restart → 1); consolidated
path is live in one process (0 → ingest → 1, no restart). The pair is the whole
justification for consolidated-runtime-v0.
