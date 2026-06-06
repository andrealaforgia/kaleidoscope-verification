# LQ09 — logs-severity-case-and-compose

## Surface

`crates/log-query-api` binary (`/api/v1/logs` filtering), via the
gateway → Lumen → log-query-api round-trip.

## Behaviour

Over a known mixed-severity/body fixture:
- `min_severity` is case-insensitive: `min_severity=warn` returns exactly
  the same records as `min_severity=WARN` (UC-LOG-003);
- `min_severity` and `body_contains` COMPOSE — both filters apply:
  `min_severity=ERROR&body_contains=db` returns only the ERROR record
  whose body contains `db`, excluding the INFO/`db` record (severity
  floor) and the other ERROR record (body filter), where `body_contains=db`
  alone would have kept the INFO/`db` record too (UC-LOG-018).

## Source

- External contract anchor: log-query-api filter composition + severity
  parsing.
- Use-case anchor: `kaleidoscope-usecases` UC-LOG-003/018.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`6a54ae1`).
- Method: ingest INFO/WARN/ERROR records with distinct bodies via the
  gateway; `warn` count == `WARN` count (18, >0); `ERROR&db` returns only
  `lq09-db-error` (6) while `db` alone also kept `lq09-db-info` (12).

## Evidence

- [`evidence/sev-lower.json`](evidence/sev-lower.json), [`evidence/sev-upper.json`](evidence/sev-upper.json) — case-insensitive equality.
- [`evidence/body-db.json`](evidence/body-db.json), [`evidence/compose.json`](evidence/compose.json) — compose narrows the set.

## Issues

None.

## Notes

`.no-compose` marker; built via `harness/run-eg.sh` (needs the gateway
image to ingest). Complements LQ05 (severity floor across the durable
boundary) and LQ02 (body_contains round-trip).
