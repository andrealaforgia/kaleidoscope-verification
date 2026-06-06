# K34 — cli-tier-observe-otlp-audit

## Surface

`kaleidoscope-cli` operator binary (`migrate`/`evaluate-policy`
`--observe-otlp`). Audit-trail / self-observability.

## Behaviour

The Cinder tiering commands emit an OTLP-JSON audit trail via
`--observe-otlp`:
- `migrate` appends one `cinder.migrate.count` line carrying `from`/`to`
  tier attributes and the `tenant_id` resource attribute (UC-CLIOBS-003,
  UC-CLIOBS-007);
- `evaluate-policy` appends one `cinder.migrate.count` line PER migration
  it performs, plus a `cinder.evaluate.migrated.count` summary carrying
  the total (`asInt`) (UC-CLIOBS-004);
- the observation file is append-only across runs — a second command
  writing the same file keeps the first run's lines (UC-CLIOBS-005).

## Source

- External contract anchor: `kaleidoscope-cli` `--observe-otlp` emission
  on the tiering subcommands (cinder.migrate.count / evaluate summary).
- Use-case anchor: `kaleidoscope-usecases` UC-CLIOBS-003/004/005/007.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`b058a34`).
- Method: migrate twice to the same obs file (hot→warm then warm→cold) →
  2 append-only lines with the right from/to; place 2 hot items and
  `evaluate-policy 0 0` → 2 `cinder.migrate.count` lines + a `migrated=2`
  summary.

## Evidence

- [`evidence/obs.ndjson`](evidence/obs.ndjson) — migrate audit (append-only).
- [`evidence/evobs.ndjson`](evidence/evobs.ndjson) — evaluate-policy per-migration + summary.

## Issues

None.

## Notes

`.no-compose`. Complements K05/K10/K12 (ingest/read observe). UC-CLIOBS-006
(emitted OTLP-JSON itself re-ingestible) is 🟡 in the catalogue and left
to the dogfooding path.
