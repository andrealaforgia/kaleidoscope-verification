# K06 — kaleidoscope-cli-stats-populated-tenant

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

After ingesting N records for a tenant, `kaleidoscope-cli stats
<tenant> <data-dir>` prints three lines: `records=N`,
`earliest=<ISO 8601>`, and `latest=<ISO 8601>`, derived from the
on-disk segments produced by `ingest`.

## Source

- External contract anchor: commit `75f15a6` ("feat(kaleidoscope-cli):
  stats subcommand for quick tenant inspection").
- Code: `crates/kaleidoscope-cli/src/main.rs` (`run_stats`).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-19 UTC at HEAD (`4734992`).
- Method: ingest three NDJSON records via `docker run … ingest`,
  then invoke `docker run … stats acme /data` and assert each
  expected prefix appears in stdout.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K06.stdout.txt`](evidence/K06.stdout.txt) — runner trace.
- [`evidence/stats.out`](evidence/stats.out) — raw stats output.

## Issues

None.

## Notes

`.no-compose` marker — kaleidoscope-cli is a self-contained
binary; no compose stack needed.
