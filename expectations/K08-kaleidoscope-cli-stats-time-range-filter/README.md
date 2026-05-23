# K08 — kaleidoscope-cli-stats-time-range-filter

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli stats <tenant> <data-dir> --since <ISO 8601>
--until <ISO 8601>` reports `records=N` and `earliest`/`latest`
constrained to the half-open interval `[since, until)`.

## Source

- External contract anchor: commit `9d1f805` ("feat(kaleidoscope-cli):
  stats --since/--until ISO 8601 time-range filter").
- Code: `crates/kaleidoscope-cli/src/main.rs` (`run_stats`).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-19 UTC at HEAD (`4734992`).
- Method: ingest three records, then run `stats` with a window
  that selects exactly the middle one. Assert `records=1` plus
  the bounds match.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K08.stdout.txt`](evidence/K08.stdout.txt) — runner trace.
- [`evidence/stats.out`](evidence/stats.out) — raw stats output.

## Issues

None.

## Notes

`.no-compose` marker. The `--since`/`--until` semantics for
`stats` match `read` (K07) — same half-open interval, same ISO
8601 parsing path.
