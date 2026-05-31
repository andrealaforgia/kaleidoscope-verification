# LQ03 — logs-body-regex-round-trip

## Surface

kaleidoscope-gateway (OTLP receiver, Lumen sink) + log-query-api
(`/api/v1/logs` over Lumen). End-to-end, operator/integrator-facing.

## Behaviour

Given a log record with a known body is ingested through the gateway
into the durable Lumen store
When log-query-api is queried with `body_regex=<pattern>` over the same
store and tenant
Then the response selects the record by REGEX semantics, not mere
substring: the SAME body `lq03-needle-ziggurat` (which contains
`...iggu...`) is returned for `body_regex=ig{2}u` and excluded for the
stricter `body_regex=ig{3}u`. Both queries return `200`; the first is
non-empty with every body matching the pattern, the second is `[]`.

A substring filter cannot express `{2}` versus `{3}` on the same
characters. The only way the stricter pattern returns `[]` while the
looser one returns rows is if the regex engine is genuinely applied
server-side. That is what LQ03 pins; LQ02 did the same for the
substring filter, and LQ01 for the mutual-exclusion guard.

## Source

- kaleidoscope `cf0ac15..35c314a`: log-body-regex-search landed as a real
  feature (feat `6cecd63`, ADR-0056 `body_regex`).
- External contract anchor:
  [`crates/log-query-api/src/lib.rs:224`](https://github.com/andrealaforgia/kaleidoscope/blob/4e4060e522420e95ea738424bf4bbabe883843e3/crates/log-query-api/src/lib.rs#L224)
  (`parse_body_regex` → `Predicate::new().body_regex(re)`,
  `Regex::is_match`, unanchored, byte-wise case-sensitive).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-30 UTC at HEAD (`4e4060e`, clean). GREEN at
  first attempt: `body_regex=ig{2}u` returned 11 records all matching;
  the stricter `ig{3}u` on the same bodies returned `[]`.
- Method: dockerised harness via `harness/run-eg.sh` (gateway +
  log-query-api built from the HEAD snapshot, the latter via the
  catalogue-authored `harness/Dockerfile.log-query-api`). Gateway on host
  port `14319`, one batch of OTLP/HTTP logs with
  `--body lq03-needle-ziggurat` via `telemetrygen:v0.114.0`, SIGTERM to
  flush Lumen, then log-query-api on the SAME `/data` (host port `19092`)
  queried twice. The regex query params are sent with
  `curl -G --data-urlencode` so the `{` `}` metacharacters survive intact.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `4e4060e`, dirty `no`).
- [`evidence/lq03-match.json`](evidence/lq03-match.json) — the `ig{2}u`
  response; element 0 carries `"body":"lq03-needle-ziggurat"`.
- [`evidence/lq03-absent.json`](evidence/lq03-absent.json) — the `ig{3}u`
  empty array.
- [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt),
  [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt)
  (the last is empty; no tracing subscriber, see
  [`issue 005`](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)).

## Issues

None.

## Notes

Binds unique high host ports (`14319`, `19092`) per N27 to avoid the
dev-side `kaleidoscope-e2e` port squatter. Sibling of LQ02 on the same
fixture.
