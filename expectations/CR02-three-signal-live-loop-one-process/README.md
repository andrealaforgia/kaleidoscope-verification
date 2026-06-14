# CR02 — three-signal-live-loop-one-process

## Surface

The consolidated runtime binary (`kaleidoscope`, crate `kaleidoscope-runtime`,
consolidated-runtime-v0 slice 2 / ADR-0076; closes C1). Single-process live loop
for all three signals.

## Behaviour

One `kaleidoscope` process holds the pulse/lumen/ray stores and `Arc::clone`s
each into both the OTLP ingest sink and the matching query router, so metrics,
logs AND traces ingested into the process are each immediately queryable from
their own router with no restart.

One container, never restarted:

- **metrics** (the continuous-live-state sharpening, implementer msg 037):
  `gen` absent before ingest (0 series); after one metric (svc `cr02svc1`) → 1
  series; after a SECOND, post-query metric (svc `cr02svc2`) → 2 series —
  strictly more, so a later ingest is visible without restart (continuous shared
  state, not a one-time startup load).
- **logs**: `body_contains=<needle>` empty before ingest (0); after
  telemetrygen logs → 6 records on :9091.
- **traces**: `service=<svc>` empty before ingest (0); after telemetrygen traces
  → 10 spans on :9092.
- the container `StartedAt` is identical across the whole loop → no restart.

## Source

- kaleidoscope `consolidated-runtime-v0` slice 2 (`2a74e4f`, archived
  `db044bf`): `crates/kaleidoscope-runtime` — logs + traces live on the shared
  lumen/ray stores, the three-signal capstone.
- Contract anchor: ADR-0076 DD2 (shared-Arc live visibility). In-process
  counterpart: `tests/slice_02_live_logs_traces.rs`.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at HEAD `db044bf` (code `2a74e4f`). `m_pre=0
  m_after1=1 m_after2=2`; `l_pre=0 l_after=6`; `t_pre=0 t_after=10`;
  `started_before == started_after`.
- Transition-proof: RED if any signal is not live (post-ingest empty), if the
  second metric ingest is not visible without restart (continuous-state
  falsified), or if the process restarted.
- Method: `harness/run-kaleidoscope-runtime.sh` builds the `kaleidoscope` image
  (`--locked`); the runner boots one container (`KALEIDOSCOPE_TENANT=acme`,
  ports 4318 + 9090/9091/9092), queries each signal before ingest, ingests via
  telemetrygen to :4318 (metrics twice), re-queries each, and asserts the counts
  + unchanged `StartedAt`.

## Notes

Companion to CR01 (the metrics live loop in detail). `.no-compose`: CR02 manages
its own single container. Still queued from implementer msg 037: CR03 — the
regression negative control (the separate gateway + query-api path must NOT show
a post-boot ingest until restart, the differential that proves the consolidated
fix is real), plus tenant isolation in one process and fail-closed startup on a
port conflict.
