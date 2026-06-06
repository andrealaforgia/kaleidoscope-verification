# K26 — cli-read-half-open-interval

## Surface

`kaleidoscope-cli` operator binary (`read --since/--until` filtering).

## Behaviour

`read` honours the documented half-open `[since, until)` window: a record
exactly at `--since` is included (since inclusive), a record exactly at
`--until` is excluded (until exclusive), and with no flags the full range
is returned.

Covers **UC-RANGE-002** (half-open semantics) and **UC-RANGE-003**
(default range is everything).

## Source

- External contract anchor: `kaleidoscope-cli` `run_read` TimeRange
  filtering; usage header (`half-open interval [since, until)`).
- Use-case anchor: `kaleidoscope-usecases` UC-RANGE-002/003.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: ingest t0 (22:13:20Z) and t60 (22:14:20Z); no flags → {t0,t60};
  `--since 22:13:20Z` → {t0,t60} (t0 included); `--until 22:14:20Z` →
  {t0} (t60 excluded).

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/default.out`](evidence/default.out), [`evidence/since-t0.out`](evidence/since-t0.out), [`evidence/until-t60.out`](evidence/until-t60.out).

## Issues

None.

## Notes

`.no-compose` marker.
