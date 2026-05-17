# K05 — kaleidoscope-cli-observe-otlp-emits-ndjson

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

Invoking `kaleidoscope-cli ingest <tenant> <data_dir> --observe-otlp <path>` writes one NDJSON OTLP-JSON ResourceMetrics line per batch flush to <path>. Each line is a self-contained ResourceMetrics object (resource attributes + scopeMetrics + metrics with sum/dataPoints). Operators can `tail -f` and forward to a real OTLP/HTTP collector via a sidecar.

## Source

- External contract anchor: [`crates/self-observe/src/lumen_to_otlp_json.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/crates/self-observe/src/lumen_to_otlp_json.rs) and the K05 runner's captured `evidence/observed.ndjson`.

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
- [`evidence/K05.stdout.txt`](evidence/K05.stdout.txt) — runner trace.
- [`evidence/K05.build.txt`](evidence/K05.build.txt) — docker build log.
- Plus scenario-specific captures (see runner.sh for the exact
  filenames it produces in `evidence/`).

## Issues

None.

## Notes

`.no-compose` marker — kaleidoscope-cli is a self-contained
binary; no compose stack needed.
