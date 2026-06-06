# G04 — gateway-pillar-root-resolution

## Surface

`crates/kaleidoscope-gateway` binary, startup pillar-root resolution.

## Behaviour

The gateway resolves its pillar root from a CLI positional argument
(UC-GWLIFE-001) and from `KALEIDOSCOPE_PILLAR_ROOT` (UC-GWLIFE-002), and
creates the durable pillars under the resolved root. The structured
`gateway_starting` event reports the resolved `pillar_root`, and the
pillar files (`lumen.snapshot`, `pulse/`, `ray.snapshot`, …) appear under
it. The CLI positional overrides the image's
`ENV KALEIDOSCOPE_PILLAR_ROOT=/data` (precedence).

## Source

- External contract anchor: gateway main pillar-root resolution
  (arg > env > default).
- Use-case anchor: `kaleidoscope-usecases` UC-GWLIFE-001/002.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`bb33b95`).
- Method: start the gateway with positional `/data/cliroot` → event
  `pillar_root=/data/cliroot` and pillars created there; start with
  `KALEIDOSCOPE_PILLAR_ROOT=/data/envroot` → `pillar_root=/data/envroot`.

## Evidence

- [`evidence/cli.stderr.txt`](evidence/cli.stderr.txt), [`evidence/cli.pillars.txt`](evidence/cli.pillars.txt), [`evidence/env.stderr.txt`](evidence/env.stderr.txt).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-gateway.sh`. UC-GWLIFE-003 (the
binary default `kaleidoscope-data/`) is not black-box reachable through
this image, which pins `ENV KALEIDOSCOPE_PILLAR_ROOT=/data`; left to
in-suite tests.
