# G05 — gateway-graceful-drain-sigterm-sigint

## Surface

`crates/kaleidoscope-gateway` binary, signal handling / shutdown.

## Behaviour

The gateway drains gracefully and exits 0 on SIGTERM (UC-GWLIFE-004), and
runs the same drain path to exit 0 on SIGINT (UC-GWLIFE-005). No half-open
process is left behind. The gateway analogue of aperture's A11-A13.

## Source

- External contract anchor: gateway shutdown / drain orchestration.
- Use-case anchor: `kaleidoscope-usecases` UC-GWLIFE-004/005.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`bb33b95`).
- Method: boot the gateway to `listener_bound`; `docker stop` (SIGTERM)
  → exit 0; boot again and `docker kill -s INT` (SIGINT) → exit 0, not
  running.

## Evidence

- [`evidence/G05.stdout.txt`](evidence/G05.stdout.txt) — exit codes.
- [`evidence/sigterm.stderr.txt`](evidence/sigterm.stderr.txt), [`evidence/sigint.stderr.txt`](evidence/sigint.stderr.txt).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-gateway.sh`. The container runs
without `--rm` so the exit code is inspectable after it stops.
