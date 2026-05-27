# 007 — S03 aperture `/readyz=200` timeout under compose harness at `91d3daa`

- Status: `closed` (flake, not regression)
- Closed: 2026-05-27. Cycle 7 cold retry of S03 GREEN at first
  attempt (`tenant.id observed: acme-prod-S03`). Same
  disposition as issue 006: docker desktop resource pressure
  late in a heavy compose-churn cycle is enough to time out
  aperture's `/readyz` poll; a fresh docker state recovers.
- Expectations affected: S03 (broken at cycle 6 of overnight loop).
- Opened: 2026-05-27
- Kaleidoscope SHA at observation: `91d3daa`

## Observed

S03 (`tenant-id-on-resource-when-required`) failed deterministically
across two consecutive runs at `91d3daa`:

```
 Container kaleidoscope-expectations-aperture-1 Started
waiting for aperture /readyz=200 (centralised, ≤ 180 s)
aperture never reached /readyz=200 within the centralised window
```

In the same cycle, A11, A12, S02, X10 all GREEN — A12 uses the
same compose stack as S03 and ran 60 s earlier successfully.
This is the same shape as issue 006 (A10 cycle 4): a single
compose-based expectation flakes on `/readyz` after a sequence
of other compose runs has saturated docker desktop's VM.

## Expected

S03 verifies that `spark::init` with `require_tenant_id` +
`with_tenant_id("acme")` lands `tenant.id=acme` on the
resource attribute of every emitted signal. The runner brings
up aperture + otelcol-sink + spark-consumer, runs the
canonical scenario, and asserts the resource shape on the
otelcol-sink's captured OTLP. Multiple prior cycles GREEN.

## Hypothesis

Docker desktop resource exhaustion after sustained compose
churn within a session. Issue 006 had the same shape on A10
and resolved on the next cycle once docker's VM had idle
time. The pattern: late in a heavy cycle, one compose
expectation flakes; isolated retry in the next cycle passes.

## Next action

Next cycle re-tries S03 first (cold docker state). If GREEN,
close issue 007 as flake (same disposition as issue 006). If
still broken, deeper investigation: aperture stderr capture
before teardown, docker-compose port-binding race.

## Catalogue impact

S03 marked `broken` until next cycle confirms or denies the
flake. A11, A12, S02 remain `satisfied` (re-verified this
same cycle, GREEN).
