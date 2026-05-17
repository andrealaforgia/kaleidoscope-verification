# K01 — kaleidoscope-cli-help-exit-zero

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli --help` exits 0 and prints a usage banner naming both subcommands (`ingest` and `read`).

## Source

- External contract anchor: [`crates/kaleidoscope-cli/src/main.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/crates/kaleidoscope-cli/src/main.rs) (`print_usage` function).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-18 UTC at HEAD (`1df2d590bd07a0e2c01047e35db780ee995577dc`).
- Method: `harness/run-kaleidoscope-cli.sh` builds the runtime
  image from the HEAD snapshot via the project-shipped
  `Dockerfile` (`docker build -f .snapshot/Dockerfile .snapshot/`),
  then runs an inline scenario script per runner. Each scenario
  uses `docker run` with stdin pipes or bind-mounted data dirs,
  exactly as an operator would per the Dockerfile's documented
  usage block.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K01.stdout.txt`](evidence/K01.stdout.txt) — runner trace.
- [`evidence/K01.build.txt`](evidence/K01.build.txt) — docker build log.
- Plus scenario-specific captures (see runner.sh for the exact
  filenames it produces in `evidence/`).

## Issues

None.

## Notes

`.no-compose` marker — kaleidoscope-cli is a self-contained
binary; no compose stack needed.
