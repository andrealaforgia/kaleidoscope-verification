# K12 — kaleidoscope-cli-observe-otlp-cinder-wired

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli ingest <tenant> <data-dir> --observe-otlp
<path>` writes BOTH a Lumen metric line (`lumen.ingest.count`)
AND at least one Cinder metric line (`cinder.*`) to `<path>`.
The two writer halves (LumenToOtlpJsonWriter,
CinderToOtlpJsonWriter) share the file via `try_clone()` and
rely on POSIX `O_APPEND` for cross-writer atomicity — see
ADR-0039 §7-§8.

## Source

- External contract anchor: commit `2baa05c` ("feat(kaleidoscope-cli):
  wire Cinder events into --observe-otlp sink").
- Code: `crates/kaleidoscope-cli/src/lib.rs` (`ingest` match arm
  wires the Cinder recorder); `crates/self-observe/src/{cinder,lumen}_otlp_json.rs`
  (single-syscall line emission for O_APPEND atomicity).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-19 UTC at HEAD (`4855d69`).
- Method: pipe two NDJSON records into `docker run … ingest
  acme /data --observe-otlp /data/observed.ndjson`, then assert
  `observed.ndjson` contains both `lumen.ingest.count` and a
  line matching `"name":"cinder.*`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K12.stdout.txt`](evidence/K12.stdout.txt) — runner trace.
- [`evidence/observed.ndjson`](evidence/observed.ndjson) — captured cross-writer output.

## Issues

None.

## Notes

K12 strengthens K10. K10 only asserts `lumen.query.count` is
present on the `read` path; K12 asserts BOTH writers land on
the `ingest` path. Together they exercise the full self-observe
fan-out from kaleidoscope-cli.

The cross-writer atomicity claim is structural (POSIX O_APPEND
sub-PIPE_BUF write atomicity) and not directly observable in
this expectation. Empirical verification lives in
`crates/kaleidoscope-cli/tests/observe_otlp_cinder_wiring.rs`
(2 threads x 100 emissions); K12 tests presence, not race
behaviour.

`.no-compose` marker.
