# M1LOOP — make-up-demo-see (the one-command Milestone-1 loop)

## Surface

The experimentable-stack one-command experience (ADR-0077): bring the
consolidated stack up, push sample telemetry, see it. Driven by the project's
own `compose.yaml` + `Dockerfile.runtime` + the seed (generator) service.

## Behaviour

- the stack comes up healthy with Prism served **same-origin** (an HTML SPA
  document on the metrics/query port; Prism and `/api/v1` share one origin);
- the query API answers (empty `200`) once up;
- the seed (the first-party generator) pushes sample telemetry, and all three
  signals become queryable: `request_count` (metrics), the `card declined` log,
  and the `kaleidoscope-demo` trace.

## How to run

```
cd ~/dev/kaleidoscope-expectations
KALEIDOSCOPE_REPO=~/dev/kaleidoscope bash harness/run-expectation.sh M1LOOP
```

It builds and starts the project's compose stack from the committed HEAD
snapshot under a catalogue port-isolation override (drops the OTLP ingest host
ports — the seed reaches the runtime on the internal network — and remaps the
three query ports to high host ports, so it never collides with a separately
running canonical stack while preserving same-origin Prism), runs the seed, and
queries the three signals.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `3658376` (generator
  `4eacfb8`). `compose up` → runtime `Healthy`; `prism_root=200` (HTML SPA),
  `query_up=200`; after seed: `demo_metrics=1 demo_logs=1 demo_traces=1`.
- Method: the project's `compose.yaml` + `Dockerfile.runtime` (rust runtime +
  the Prism node/pnpm build, same-origin) + the seed service, run with a
  port-isolation override; assert the SPA HTML, the query API, and the three
  signals.

## Notes

`.no-compose` marks that the harness's own otelcol stack is skipped; M1LOOP
brings its OWN project compose stack up. A first run with the literal `make up`
failed only on a port collision with a separately-running canonical stack
(`kaleidoscope-runtime-1`, the team's) — not a defect; the override makes the
loop port-isolated and repeatable. The query/signals half overlaps CRGEN01; what
M1LOOP adds is the make/compose/Prism orchestration end to end.
