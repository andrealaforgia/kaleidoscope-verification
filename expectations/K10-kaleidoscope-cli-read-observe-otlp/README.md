# K10 — kaleidoscope-cli-read-observe-otlp

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli read <tenant> <data-dir> --observe-otlp
<path>` appends OTLP-JSON NDJSON lines to `<path>`, including
at least one `lumen.query.count` metric event per invocation —
emitted by the self-observe `LumenToOtlpJsonWriter` bridge as
the read path drives Lumen's query recorder.

## Source

- External contract anchor: commit `8ee7091` ("feat(kaleidoscope-cli):
  read --observe-otlp wires Lumen query events to OTLP-JSON").
- Code: `crates/kaleidoscope-cli/src/main.rs` (`run_read_with`,
  `parse_observe_otlp`), `crates/self-observe/src/*`.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-19 UTC at HEAD (`4734992`).
- Method: ingest one record, then `read --observe-otlp
  /data/observed.ndjson`, then assert `lumen.query.count` is
  present in the produced file.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K10.stdout.txt`](evidence/K10.stdout.txt) — runner trace.
- [`evidence/observed.ndjson`](evidence/observed.ndjson) — captured OTLP-JSON sink output.

## Issues

None.

## Notes

`.no-compose` marker. This is the only operator-facing exercise
of the self-observe crate's OTLP-JSON sink — see [N13] for the
self-observe / pillar story.

A follow-up expectation could cover the Cinder side of the
sink (added by commit `2baa05c` — "wire Cinder events into
--observe-otlp sink"), checking that ingest also emits a
`cinder.*` metric line. Tracked as a candidate K12.
