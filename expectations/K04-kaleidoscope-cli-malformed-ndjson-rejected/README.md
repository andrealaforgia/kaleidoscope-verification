# K04 — kaleidoscope-cli-malformed-ndjson-rejected

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

When an input line is not valid JSON, `kaleidoscope-cli ingest` exits non-zero (`ExitCode::FAILURE`) and emits a `ParseRecord` diagnostic on stderr naming the failing line. Operators can grep the diagnostic to find the bad line in their input.

## Source

- External contract anchor: [`crates/kaleidoscope-cli/src/lib.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/crates/kaleidoscope-cli/src/lib.rs) (`Error::ParseRecord { line, source }` variant).

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
- [`evidence/K04.stdout.txt`](evidence/K04.stdout.txt) — runner trace.
- [`evidence/K04.build.txt`](evidence/K04.build.txt) — docker build log.
- Plus scenario-specific captures (see runner.sh for the exact
  filenames it produces in `evidence/`).

## Issues

None.

## Notes

`.no-compose` marker — kaleidoscope-cli is a self-contained
binary; no compose stack needed.
