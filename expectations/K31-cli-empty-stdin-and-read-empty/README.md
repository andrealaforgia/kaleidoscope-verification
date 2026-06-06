# K31 — cli-empty-stdin-and-read-empty

## Surface

`kaleidoscope-cli` operator binary (`ingest`, `read`).

## Behaviour

Empty-stdin `ingest` is a no-op success: `ingest ok: records=0
batches=0 tier_items=0`, exit 0, store left valid. A subsequent `read`
of the now-initialised store returns nothing on stdout with
`read ok: records=0`.

Covers **UC-CLI-014** (empty stdin no-op success) and **UC-CLI-007**
(read an empty store).

## Source

- External contract anchor: `kaleidoscope-cli` `run_ingest` empty-input
  path / `run_read` empty-store path.
- Use-case anchor: `kaleidoscope-usecases` UC-CLI-014/007.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: `: | ingest acme /data` → records=0, exit 0; `read acme /data`
  → empty stdout, `read ok: records=0`, exit 0.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/ingest.out`](evidence/ingest.out), [`evidence/read.out`](evidence/read.out), [`evidence/read.err`](evidence/read.err).

## Issues

None.

## Notes

`.no-compose` marker.
