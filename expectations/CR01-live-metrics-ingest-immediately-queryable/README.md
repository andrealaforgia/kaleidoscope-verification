# CR01 — live-metrics-ingest-immediately-queryable

## Surface

The consolidated runtime binary (`kaleidoscope`, crate `kaleidoscope-runtime`,
consolidated-runtime-v0 / ADR-0076). Operator-facing single-process live loop.

## Behaviour

One `kaleidoscope` process builds one Pulse store and `Arc::clone`s the same
instance into both the OTLP ingest sink (HTTP :4318) and the metrics query
router (:9090). So a metric ingested into the process is **immediately
queryable from the same process, with no restart** — the falsifiable
differential against the split deployment (EG01), where the gateway must be
SIGTERM'd to flush before a separate query-api can read.

Scenario, one container, never restarted:

1. boot `kaleidoscope` with `KALEIDOSCOPE_TENANT=acme`.
2. query `gen` BEFORE ingest → `200 success`, 0 series (the metric is not
   pre-present; the empty store answers, so the query side is live from boot).
3. telemetrygen one `gen` metric → :4318 (OTLP/HTTP).
4. query `gen` AFTER ingest, same running process → `200 success`, 1 series.
5. the container `StartedAt` is identical before and after → the process never
   restarted; the visibility came from the shared `Arc`, not a reopen.

## Source

- kaleidoscope `consolidated-runtime-v0` slice 1 (`fbcacca`):
  `crates/kaleidoscope-runtime/src/{lib.rs,main.rs}` (one tokio runtime, one
  store per signal Arc-cloned into sink + router).
- Contract anchor: ADR-0076 DD2 (shared-Arc live visibility), DD3 (fail-closed
  wire→probe→use startup). In-process counterpart:
  `tests/slice_01_live_metrics.rs`.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `fbcacca`. `pre_code=200
  pre_status=success pre_count=0`; `post_code=200 post_status=success
  post_count=1`; `started_before == started_after` (identical container
  `StartedAt`, so no restart between ingest and query).
- Transition-proof: RED if the post-ingest query returns 0 series (no live
  visibility, ADR-0076 DD2 falsified) or if the container restarted between the
  two queries.
- Method: `harness/run-kaleidoscope-runtime.sh` injects the catalogue-authored
  `harness/Dockerfile.kaleidoscope-runtime` into the HEAD snapshot and builds
  the `kaleidoscope` binary (`cargo build --release -p kaleidoscope-runtime
  --locked`); the runner boots one container, queries before ingest, ingests via
  telemetrygen to :4318, re-queries the same process, and asserts the counts +
  unchanged `StartedAt`.

## Notes

The project ships no Dockerfile for the consolidated runtime (the root
`Dockerfile` builds `kaleidoscope-cli`), so the image is catalogue-authored,
modelled verbatim on the project's `Dockerfile.query-api`. The query routers
bind quietly — only the ingest aperture listeners emit a `listener_bound` event
— so readiness is polled on the HTTP query surface (a well-formed range query
returns `200`), not on the log. `.no-compose`: CR01 manages its own single
container. Slice 2 (live logs + traces) is the same loop on the lumen/ray
stores; a CR02 will exercise it.
