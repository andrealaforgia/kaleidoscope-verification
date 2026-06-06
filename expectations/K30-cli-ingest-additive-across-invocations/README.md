# K30 — cli-ingest-additive-across-invocations

## Surface

`kaleidoscope-cli` operator binary (`ingest` ×2, `read`).

## Behaviour

Two separate `ingest` runs into the same data dir are additive: the
second appends rather than overwriting. A subsequent `read` returns both
batches (`first` and `second`).

Covers **UC-CLI-006** (ingest is additive across invocations). The
separate read container also exercises **UC-CLI-008** (survives restart).

## Source

- External contract anchor: `kaleidoscope-cli` `run_ingest` append
  semantics (Lumen WAL append).
- Use-case anchor: `kaleidoscope-usecases` UC-CLI-006 (+008).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: ingest `first`, then ingest `second` into the same dir; read →
  both bodies present.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/ingest-1.out`](evidence/ingest-1.out), [`evidence/ingest-2.out`](evidence/ingest-2.out), [`evidence/read.out`](evidence/read.out).

## Issues

None.

## Notes

`.no-compose` marker.
