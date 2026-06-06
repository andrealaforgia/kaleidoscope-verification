# K29 — cli-ingest-batch-no-loss

## Surface

`kaleidoscope-cli` operator binary (`ingest`, `read`).

## Behaviour

A large ingest whose count is not a multiple of the 100-record batch
size (250) loses no records at batch boundaries: `ingest` reports
`records=250`, and a fresh `read` container returns all 250 in ascending
order (`b0`..`b249`).

Covers **UC-CLI-004** (batch of many), **UC-CLI-005** (all returned in
order), **UC-CLI-013** (250 not divisible by 100, no batch-boundary
loss). The read runs in a separate container, so it also exercises
**UC-CLI-008** (records survive a process restart).

## Source

- External contract anchor: `kaleidoscope-cli` `run_ingest` batching
  (100-record batches) / `run_read`.
- Use-case anchor: `kaleidoscope-usecases` UC-CLI-004/005/013 (+008).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: generate 250 NDJSON lines, ingest → `records=250`; read in a
  fresh container → 250 rows, first `b0`, last `b249`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/ingest.out`](evidence/ingest.out), [`evidence/read.out`](evidence/read.out).

## Issues

None.

## Notes

`.no-compose` marker.
