# 006 — aperture `/readyz=200` never reached within 180 s under the compose harness at `0091975`

- Status: `closed` (flake, not regression)
- Closed: 2026-05-27. Cycle 5 of the overnight loop re-verified
  A01, A02, A03, A04, A11 all GREEN at HEAD `b71ad8a`, and A10
  itself recovered on the first retry. The cycle-4 double-fail
  was likely docker desktop transient (cache loss / network
  pressure) rather than an aperture regression.
- Expectations affected: A10 (broken at cycle 4 of overnight loop).
- Opened: 2026-05-27
- Kaleidoscope SHA at observation: `0091975c5d60c35416124cecf4f7113136caef86`

## Observed

A10 (`readyz-200-when-healthy`) failed deterministically across
two consecutive runs at `0091975`:

```
 Container kaleidoscope-expectations-aperture-1 Started
waiting for aperture /readyz=200 (centralised, ≤ 180 s)
aperture never reached /readyz=200 within the centralised window
```

The aperture container's stderr in evidence is empty. The
container is auto-cleaned by the failing harness teardown, so
no post-mortem `docker logs` survives.

Standalone `docker run --rm aperture:under-test --config
<harness-aperture.toml>` exits 0 with no output. That is
itself unusual — aperture should bind listeners and wait for
SIGTERM, not exit on its own. Possible regression in
aperture's run loop, or a quiet fail-closed of the forwarding
sink probe with no otelcol-sink reachable in standalone mode.

## Expected

A10's runner brings up the compose stack (aperture + otelcol-
sink), waits for aperture's `/readyz=200`, sends OTLP traffic,
and asserts a healthy response. Pre-`0091975` runs of A10 in
cycle 3 / cycle 1 were GREEN.

## Reproduction

```
cd ~/dev/kaleidoscope-expectations
KALEIDOSCOPE_DIR=$HOME/dev/kaleidoscope ./harness/run-expectation.sh A10
# observe: "aperture never reached /readyz=200"
```

## Hypotheses to explore

- Has the aperture binary's startup sequence regressed
  (sink-wiring panics, listener bind fails silently before
  readiness flips)?
- Is there a new ENV variable required at startup that the
  harness's compose config does not pass through?
- Is otelcol-sink (the downstream the forwarding probe dials)
  reachable on the compose network at startup time?

Next cycle: instrument aperture stderr capture before
teardown so the failure mode is visible.

## Catalogue impact

A10 marked `broken` until the root cause is identified. Other
A-prefix expectations (A01-A06, A08, A11-A13, A15, A16) all
use the same compose stack; if this is a real aperture
regression rather than A10-specific, they will fall as the
next cycle re-verifies them.
