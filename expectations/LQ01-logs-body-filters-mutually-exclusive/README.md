# LQ01 — logs-body-filters-mutually-exclusive

## Surface

log-query-api (Lumen logs read HTTP service). Operator/integrator-facing.

## Behaviour

Given log-query-api is running with a resolved tenant and a freshly
opened, empty Lumen store
When an integrator issues `GET /api/v1/logs` with a valid window and
**both** `body_contains` and `body_regex` present
Then the service refuses with HTTP `400` and a `status:error` body whose
`error` is the literal `specify body_regex or body_contains, not both`,
and the store is never queried on that path.
And when exactly one of the two body filters is present (with the same
valid window), the service accepts the request with `200`.

This pins the mutual-exclusion contract: the two body filters are
siblings, exactly one may be present. The single-filter `200` control
observations prove the `400` is specifically the mutual-exclusion arm,
not a blanket rejection of body filtering.

## Source

- kaleidoscope diff `cf0ac15..35c314a` (autonomous cycle 31): the
  log-body-text-search and log-body-regex-search slices landed as real
  features on the running surface.
- External contract anchor: ADR-0056 Decision 7 / DD4 (mutual
  exclusion), implemented at
  [`crates/log-query-api/src/lib.rs:210`](https://github.com/andrealaforgia/kaleidoscope/blob/35c314ae9533b99ad7be45647127d74ffd57cae8/crates/log-query-api/src/lib.rs#L210)
  (`if body_contains.is_some() && params.body_regex.is_some()`),
  design commit `ca25818`, feat commits `1bfa609` (body_contains) and
  `6cecd63` (body_regex).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-29 UTC at HEAD (`35c314a`). GREEN at first
  attempt: `code_a_contains=200`, `code_b_regex=200`,
  `code_c_both=400` with the verbatim reason
  `specify body_regex or body_contains, not both`.
- Method: dockerised harness. log-query-api is built from the HEAD
  snapshot (`git archive HEAD`) via the catalogue-authored
  `harness/Dockerfile.log-query-api`, modelled verbatim on the
  project's own `Dockerfile.query-api`. The kaleidoscope project ships
  no Dockerfile for log-query-api at HEAD, so the catalogue stands the
  binary up itself; the binary, workspace, and `Cargo.lock` are all the
  project's own. The shared driver `harness/run-log-query-api.sh`
  injects that Dockerfile into the snapshot, builds the image, and runs
  a three-shot scenario against a fresh empty `/data` (Lumen pillar
  root) with `KALEIDOSCOPE_LOG_QUERY_TENANT=acme`: single
  `body_contains`, single `body_regex`, then both together.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `35c314a`, dirty `yes` but the dirty set is docs-only —
  `docs/feature/gate-5-mutants-batch-v0/discuss/*` — and the build used
  `git archive HEAD`, so no log-query-api source differs from the
  recorded SHA; see `evidence/kaleidoscope-dirty.status`).
- [`evidence/LQ01.stdout.txt`](evidence/LQ01.stdout.txt) — the three
  HTTP codes and the both-filters response body.
- [`evidence/lq01-a-contains.json`](evidence/lq01-a-contains.json),
  [`evidence/lq01-b-regex.json`](evidence/lq01-b-regex.json) — the two
  single-filter `200` responses (empty result array on the empty store).
- [`evidence/lq01-c-both.json`](evidence/lq01-c-both.json) — the
  mutual-exclusion `400` `status:error` envelope.
- [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt)
  — the service's own container log during the run. It is **empty**:
  `crates/log-query-api/src/main.rs` installs no `tracing` subscriber
  at HEAD, so the `log_query_api_starting` / `listener_bound` events it
  emits via `tracing::info!` are dropped, exactly the query-api pattern
  recorded in
  [`issue 005`](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md).
  LQ01 asserts only on the HTTP status + body, which is unaffected.
- [`evidence/LQ01.build.txt`](evidence/LQ01.build.txt) — image build log.

## Issues

None.

## Notes

First expectation on the log-query-api surface. The historic gap notes
(N23/N26) framed this surface as blocked on a project-shipped
Dockerfile. That framing was lazy: log-query-api has a binary target
and an axum listener at HEAD, so the catalogue can stand it up itself,
exactly as it already does for query-api. Body-filter round-trip on a
seeded store (a record that matches `body_contains` and is returned;
one that does not and is excluded) is the natural LQ02 candidate; it
needs a seeded Lumen store, which is the same fixture the durability
set (#17) will need.
