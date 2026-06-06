# K25 — cli-read-timestamp-strict-iso8601

## Surface

`kaleidoscope-cli` operator binary (`read --since/--until` timestamp parse).

## Behaviour

`--since`/`--until` accept only canonical ISO-8601 UTC. Fractional
seconds (1-9 digits) parse and filter correctly. Lower-case `z` and the
`+00:00` offset form are rejected with a non-zero exit and a precise
position diagnostic:
`invalid ISO 8601 punctuation at position 19: expected 'Z', got 'z'`
(and `got '+'` for the offset form).

Covers **UC-RANGE-008** (fractional accepted), **UC-RANGE-009**
(lowercase z rejected), **UC-RANGE-010** (+00:00 rejected).

## Source

- External contract anchor: `kaleidoscope-cli` `parse_iso8601_utc_nanos`;
  usage header (`lower-case z and +00:00 offset forms are rejected`).
- Use-case anchor: `kaleidoscope-usecases` UC-RANGE-008/009/010.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: ingest two records (t0, t60); `--since` with `.5` fractional →
  exit 0 filtered to t60; `--since ...z` and `--since ...+00:00` → exit 1
  with the position diagnostic.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/fractional.out`](evidence/fractional.out), [`evidence/lowercase-z.out`](evidence/lowercase-z.out), [`evidence/offset.out`](evidence/offset.out) and `.rc` siblings.

## Issues

None.

## Notes

`.no-compose` marker. The same strict parser backs `stats --since/--until`.
