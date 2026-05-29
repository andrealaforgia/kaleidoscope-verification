# LQ02 — logs-body-contains-round-trip

## Surface

kaleidoscope-gateway (OTLP receiver, Lumen sink) + log-query-api
(`/api/v1/logs` over Lumen). End-to-end, operator/integrator-facing.

## Behaviour

Given the gateway is running with a writable `/data` and
`KALEIDOSCOPE_DEFAULT_TENANT=acme`
When an OTLP/HTTP client emits log records carrying a known body
substring, the gateway persists them into the durable Lumen store, and
log-query-api is then started on the same `/data` with a matching tenant
Then a `GET /api/v1/logs?...&body_contains=<known-substring>` returns
`200` with a non-empty array, and **every** returned record's `body`
contains that substring
And a `GET /api/v1/logs?...&body_contains=<absent-substring>` returns
`200` with the empty array `[]`.

This proves the body filter actually FILTERS across the real durable
boundary. LQ01 proved only that `body_contains` and `body_regex` are
mutually exclusive at parse time; it never put a record through the
store. LQ02 closes that gap: the record round-trips
gateway → Lumen → log-query-api, and the filter selects it in and
selects a non-matching probe out.

## Source

- kaleidoscope `cf0ac15..35c314a`: log-body-text-search landed as a real
  feature (feat `1bfa609`, ADR-0055 `body_contains`).
- External contract anchor:
  [`crates/log-query-api/src/lib.rs:193`](https://github.com/andrealaforgia/kaleidoscope/blob/5a8b3309b7dc36cd848614c300e91074184ca8c7/crates/log-query-api/src/lib.rs#L193)
  (`parse_body_contains` → `Predicate::new().body_contains(target)`);
  gateway Lumen sink at
  [`crates/kaleidoscope-gateway/src/main.rs:67`](https://github.com/andrealaforgia/kaleidoscope/blob/5a8b3309b7dc36cd848614c300e91074184ca8c7/crates/kaleidoscope-gateway/src/main.rs#L67).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-29 UTC at HEAD (`5a8b330`). GREEN at first
  attempt after a port fix (see Notes): `body_contains=lq02-needle-ziggurat`
  returned 11 matching records, all bodies equal to the needle; a
  non-matching substring returned `[]`.
- Method: dockerised harness via `harness/run-eg.sh` (gateway +
  log-query-api both built from the HEAD snapshot; the log-query-api
  image uses the catalogue-authored `harness/Dockerfile.log-query-api`
  introduced in LQ01). The gateway is brought up on host port `14318`
  (mapped to its `:4318`), one batch of OTLP/HTTP logs with
  `--body lq02-needle-ziggurat --otlp-attributes service.name=lq02-pilot`
  is sent via the upstream `telemetrygen:v0.114.0` image, the gateway is
  SIGTERMed to flush Lumen, then log-query-api is started on the SAME
  `/data` volume (host port `19091`) and queried twice.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `5a8b330`, dirty `yes` but the dirty set is the dev side's
  in-flight gate-5 CI wave — `.github/workflows/ci.yml` + untracked
  `docs/feature/gate-5-mutants-batch-v0/devops/` — with zero
  gateway/lumen/log-query-api source; the build used `git archive HEAD`;
  see `evidence/kaleidoscope-dirty.status`).
- [`evidence/lq02-match.json`](evidence/lq02-match.json) — the matching
  query's 11-record response; element 0 carries
  `"body":"lq02-needle-ziggurat"` and `service.name=lq02-pilot`.
- [`evidence/lq02-absent.json`](evidence/lq02-absent.json) — the
  non-matching query's empty array.
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt)
  — the emitter's log.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt) — the
  gateway's container log during ingest + flush.
- [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt)
  — the read service's container log (empty; no tracing subscriber, see
  [`issue 005`](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)).
- [`evidence/LQ02.stdout.txt`](evidence/LQ02.stdout.txt),
  [`evidence/LQ02.*.build.txt`](evidence/) — scenario output and the
  three image build logs.

## Issues

None.

## Notes

The first attempt failed not on behaviour but on a port collision: a
parallel `kaleidoscope-e2e-*` compose stack (the dev side's own e2e
harness, distinct from this catalogue's `kaleidoscope-expectations`
project) was squatting host ports `4317-4318` and `9090`. Rather than
tear down containers this catalogue does not own, LQ02 binds the gateway
and log-query-api to unique high host ports (`14318`, `19091`). EG01
still uses the bare `4318`/`9090` ports and would flake under the same
squatter; hardening it the same way is tracked in `known-gaps.md` N27.

LQ03 (body_regex round-trip) and an LQ min_severity round-trip (N23) are
natural siblings on this same fixture. A fails-closed-no-tenant LQ
(mirroring Q01) is also drafabile but will hit the missing-subscriber
wall (issue 005) and must assert on the bare `Err(...)` text.
