# CRGEN03 — generator-tenant-scoping

## Surface

The generated telemetry path's tenant scoping, observed from the query surface
(`kaleidoscope-telemetrygen` → consolidated runtime).

## Behaviour

Telemetry the generator emits under tenant `acme` is queryable under `acme` and
absent under any other tenant. Same pillar root: the runtime is booted as
`acme`, the generator runs, and all three signals are visible on `acme`; then
the runtime is restarted bound to `tenant-b` over the same root and the
generated telemetry is invisible.

## Source

- kaleidoscope generator deliver `4eacfb8`, HEAD `3658376`. Observable contract
  only: data emitted under one tenant is isolated from another tenant's query.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `3658376`. `acme`:
  metrics 1 series, logs 219 records, traces 1 span — all visible. `tenant-b`:
  0 / 0 / 0 — none visible. No cross-tenant leak.
- Method: build runtime + generator from the HEAD snapshot, boot runtime as
  `acme`, run the generator, query; restart the runtime as `tenant-b` over the
  same root, query again.

## Notes

`.no-compose`. The `acme` log count (219) is the unfiltered `:9091` set — almost
all transport noise, only one application log. That is the separate FIX-A
concern (this expectation asserts tenant isolation, not log cleanliness); FIXA
grades the noise directly. Companions: CRGEN01 (send-to-see), CRGEN02
(fail-closed).
