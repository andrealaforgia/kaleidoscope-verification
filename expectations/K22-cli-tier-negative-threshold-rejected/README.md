# K22 — cli-tier-negative-threshold-rejected

## Surface

`kaleidoscope-cli` operator binary (`evaluate-policy` argument parsing).

## Behaviour

`evaluate-policy` thresholds are non-negative integer seconds. A negative
argument (`evaluate-policy /data -1 0`) is rejected as a usage error
(exit 2, usage banner) rather than silently accepted or panicking.

Covers **UC-TIER-015** (negative threshold rejected).

## Source

- External contract anchor: `kaleidoscope-cli` `run_evaluate_policy`
  argument validation; usage header (`non-negative integer seconds`).
- Use-case anchor: `kaleidoscope-usecases` UC-TIER-015.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: `evaluate-policy /data -1 0`; assert non-zero exit (2) and a
  usage diagnostic on stderr.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/negative.out`](evidence/negative.out), [`evidence/negative.rc`](evidence/negative.rc).

## Issues

None.

## Notes

`.no-compose` marker. Observed rejection is via the CLI's leading-`-`
flag guard (`unknown flag "-1"`, exit 2, usage banner) — a usage error,
satisfying UC-TIER-015's "rejected, non-negative integers only" without
asserting the specific wording.
