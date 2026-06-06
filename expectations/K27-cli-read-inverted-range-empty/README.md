# K27 — cli-read-inverted-range-empty

## Surface

`kaleidoscope-cli` operator binary (`read --since/--until`).

## Behaviour

An inverted window (`--since` after `--until`) is a calm empty result,
not an error: exit 0, `read ok: records=0` on stderr, no record lines on
stdout. The CLI does not treat an empty window as a usage failure.

Covers **UC-RANGE-011** (inverted range yields empty, not error).

## Source

- External contract anchor: `kaleidoscope-cli` `run_read` window handling.
- Use-case anchor: `kaleidoscope-usecases` UC-RANGE-011 (🟡 — behaviour
  to confirm; confirmed here as the calm-empty path).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: ingest two records; `read --since 22:14:20Z --until 22:13:20Z`
  → exit 0, empty stdout, `read ok: records=0`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/inverted.out`](evidence/inverted.out), [`evidence/inverted.err`](evidence/inverted.err), [`evidence/inverted.rc`](evidence/inverted.rc).

## Issues

None.

## Notes

`.no-compose` marker. UC-RANGE-011 was 🟡 in the catalogue (behaviour to
confirm); this pins it as the calm-empty contract.
