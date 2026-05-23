# K09 — kaleidoscope-cli-stats-cinder-tier-distribution

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli stats <tenant> <data-dir>` includes a Cinder
tier-distribution line of the form `cinder.hot=N` (and
companion tier counts where applicable), reflecting how
Cinder placed the freshly ingested records across its
hot/warm/cold tiers.

## Source

- External contract anchor: commit `946d2c8` ("feat(kaleidoscope-cli):
  stats subcommand emits Cinder tier distribution").
- Code: `crates/kaleidoscope-cli/src/main.rs` (`run_stats`),
  delegates to `cinder::Tier` accounting.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-19 UTC at HEAD (`4734992`).
- Method: ingest at least one record and confirm `cinder.hot=`
  prefix appears in stats output.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/K09.stdout.txt`](evidence/K09.stdout.txt) — runner trace.
- [`evidence/stats.out`](evidence/stats.out) — raw stats output.

## Issues

None.

## Notes

`.no-compose` marker. This is the operator-visible surface that
exercises Cinder v1's tier placement indirectly — see [N13]
in `known-gaps.md` for the broader Cinder visibility story.
