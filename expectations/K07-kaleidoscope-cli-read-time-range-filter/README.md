# K07 — kaleidoscope-cli-read-time-range-filter

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli read <tenant> <data-dir> --since <ISO 8601>
--until <ISO 8601>` returns only the NDJSON records whose
`observed_time_unix_nano` falls in the half-open interval
`[since, until)`. Records outside that interval are filtered
out.

## Source

- External contract anchor: commit `b503f49` ("feat(kaleidoscope-cli):
  read --since/--until ISO 8601 time-range filter").
- Code: `crates/kaleidoscope-cli/src/main.rs` (`run_read_with`).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-19 UTC at HEAD (`4734992`).
- Method: ingest three records at known nanosecond timestamps
  (event-a, event-b, event-c spanning 1700000000 → 1700000120),
  then `read` with `--since 2023-11-14T22:14:00Z --until
  2023-11-14T22:14:30Z`. The runner counts NDJSON-shaped lines
  (`^{`), skipping the `read ok: records=N` diagnostic line, and
  asserts exactly event-b is present.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K07.stdout.txt`](evidence/K07.stdout.txt) — runner trace.
- [`evidence/windowed.ndjson`](evidence/windowed.ndjson) — raw filtered output.

## Issues

None.

## Notes

`.no-compose` marker. The line-counting heuristic guards against
including the diagnostic; an earlier draft of the runner
miscounted by including it.
