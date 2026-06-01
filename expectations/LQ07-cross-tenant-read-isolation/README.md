# LQ07 — cross-tenant-read-isolation

## Surface

kaleidoscope-gateway (Lumen sink) + log-query-api. End-to-end,
operator/integrator-facing. Multi-tenant isolation (a security
invariant).

## Behaviour

Given logs are ingested under tenant `tenant-a` and persisted to the
Lumen store
When log-query-api reads the same store under a DIFFERENT tenant
(`tenant-b`)
Then it returns the empty array: tenant-b cannot see tenant-a's records.
And when log-query-api reads under `tenant-a`, the records are returned
— the control that proves the data IS present and durable, so the empty
result for tenant-b is ISOLATION, not merely missing data.

A multi-tenant observability platform that leaks data across tenants is
broken; this pins the isolation invariant at the running read surface,
not just in the store's unit tests.

## Source

- Per-tenant isolation in the Lumen store:
  [`crates/lumen/src/file_backed.rs:211`](https://github.com/andrealaforgia/kaleidoscope/blob/eef7576ea427e568739adc38a63257b4dafde8e0/crates/lumen/src/file_backed.rs#L211)
  — `query` / `query_with` resolve `state.per_tenant.get(tenant)`, so a
  query only ever sees its own tenant's bucket. The read API binds the
  tenant from `KALEIDOSCOPE_LOG_QUERY_TENANT`; the gateway assigns the
  ingest tenant from `KALEIDOSCOPE_DEFAULT_TENANT`.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`eef7576`). GREEN at first
  attempt: `code_b=200`, `tenant_b_count=0` (isolation),
  `code_a=200`, `tenant_a_count=6` (control: data present).
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14328` with `KALEIDOSCOPE_DEFAULT_TENANT=tenant-a` ingests
  `--body lq07-secret-marker`, SIGTERM to flush; then log-query-api on
  the SAME `/data` (host port `19103`) is started twice in sequence,
  first with `KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-b` (expect `[]`) then
  with `tenant-a` (expect the records).

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `eef7576`.
- [`evidence/lq07-tenant-b.json`](evidence/lq07-tenant-b.json) — the
  empty cross-tenant result.
- [`evidence/lq07-tenant-a.json`](evidence/lq07-tenant-a.json) — the
  same-tenant control result.
- [`evidence/LQ07.stdout.txt`](evidence/LQ07.stdout.txt) — both query
  codes and counts.

## Issues

None.

## Notes

First cross-tenant isolation expectation at the running surface. The
same shape applies to the Pulse (query-api) and Ray (trace-query-api)
read paths, which resolve their tenant identically; those would be
pattern repetition unless a pillar's isolation is suspected to differ.
Unique high host ports (`14328`, `19103`) per N27.
