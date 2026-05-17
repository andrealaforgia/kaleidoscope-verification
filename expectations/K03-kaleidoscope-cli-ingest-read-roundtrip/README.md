# K03 — kaleidoscope-cli-ingest-read-roundtrip

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

Piping NDJSON `lumen::LogRecord` lines into `kaleidoscope-cli ingest <tenant> <data_dir>`, then querying with `kaleidoscope-cli read <tenant> <data_dir>`, returns every ingested record as one NDJSON line on stdout. Body strings round-trip intact. Mirrors the operator shell pipe from the c96cb18 commit body.

## Source

- External contract anchor: [`crates/kaleidoscope-cli/tests/ingest_and_read_roundtrip.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/crates/kaleidoscope-cli/tests/ingest_and_read_roundtrip.rs).

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
- [`evidence/K03.stdout.txt`](evidence/K03.stdout.txt) — runner trace.
- [`evidence/K03.build.txt`](evidence/K03.build.txt) — docker build log.
- Plus scenario-specific captures (see runner.sh for the exact
  filenames it produces in `evidence/`).

## Issues

None.

## Notes

`.no-compose` marker — kaleidoscope-cli is a self-contained
binary; no compose stack needed.
