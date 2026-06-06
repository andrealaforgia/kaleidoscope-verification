# K32 — cli-tenant-isolation-read

## Surface

`kaleidoscope-cli` operator binary (`ingest`, `read`).

## Behaviour

Two tenants ingested into the SAME data dir stay isolated on read:
`read acme` returns only acme's records and `read globex` only globex's;
neither sees the other's data.

Covers **UC-CLI-009** (tenant isolation on the same data dir). The CLI
counterpart to LQ07/Q08/TQ05 (read-API isolation).

## Source

- External contract anchor: `kaleidoscope-cli` per-tenant Lumen keying.
- Use-case anchor: `kaleidoscope-usecases` UC-CLI-009.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: ingest `acme-rec` under acme and `globex-rec` under globex into
  one dir; `read acme` → only `acme-rec`, `read globex` → only `globex-rec`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/acme.out`](evidence/acme.out), [`evidence/globex.out`](evidence/globex.out).

## Issues

None.

## Notes

`.no-compose` marker.
