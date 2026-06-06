# K28 — cli-stats-empty-tenant

## Surface

`kaleidoscope-cli` operator binary (`stats`).

## Behaviour

`stats` over an empty or unknown tenant reports a single `records=0`
line and emits NO `earliest=`/`latest=` lines (those appear only for a
populated tenant). Exit 0.

Covers **UC-RANGE-005** (stats over an empty tenant).

## Source

- External contract anchor: `kaleidoscope-cli` `run_stats` empty-tenant
  path; usage header (`Empty tenants ... get a single line: records=0`).
- Use-case anchor: `kaleidoscope-usecases` UC-RANGE-005.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: `stats ghosttenant /data` on a fresh dir → `records=0`, assert
  no `earliest=`/`latest=` lines.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/stats.out`](evidence/stats.out), [`evidence/stats.rc`](evidence/stats.rc).

## Issues

None.

## Notes

`.no-compose` marker. Complements K06 (populated-tenant stats) and K24
(tier distribution).
