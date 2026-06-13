# QA01 — query-api-auth-config-reject-refuses-to-start

## Surface

Read path / operations. Operator-facing (deployment misconfiguration).

## Behaviour

The deployed `query-api` binary refuses to start on a broken read-auth
configuration, rather than falling through to an unauthenticated mode. Two
black-box boots of the real image:

- **partial config** — some but not all four `KALEIDOSCOPE_QUERY_AUTH_*` keys
  set (here `ISSUER` + `AUDIENCE`, missing `SECRET_FILE` + `CATALOGUE`). The
  binary exits `2` (`EXIT_CONFIG_ERROR`) and emits a structured
  `event=config_validation_failed` (level ERROR) naming **both** missing keys,
  before binding the listener.
- **unreadable secret_file** — all four keys set but `SECRET_FILE` points at a
  path absent in the container. The binary exits `2` with
  `config_validation_failed` naming the offending PATH and the io error class
  (`entity not found`), and prints **no secret byte**.

This is the negative startup probe of `read-path-query-api-auth-v0` slice 3a
(ADR-0074 DD1/DD4): a half-configured auth set is a loud refuse-to-start, not a
silent open-by-default. Mirrors aperture's `tls-config-reject` / ingest-auth
refusal precedent.

## Source

- kaleidoscope `read-path-query-api-auth-v0` slice 3a (`c389a23`),
  `crates/query-api/src/composition.rs` (`resolve_read_auth`,
  `build_read_validator`, `partial_reason`) + `src/main.rs`
  (`EXIT_CONFIG_ERROR = 2`, `event=config_validation_failed`).
- Contract anchor: ADR-0074 DD1 (composition auth config) / DD4 (negative
  startup probe). In-process counterpart: `tests/slice_08_auth_config_reject.rs`.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-13 UTC at HEAD `c389a23` (slice 3a). `partial_exit=2`
  with `{"level":"ERROR","event":"config_validation_failed","reason":"partial
  read-auth config: missing KALEIDOSCOPE_QUERY_AUTH_SECRET_FILE,
  KALEIDOSCOPE_QUERY_AUTH_CATALOGUE (all four KALEIDOSCOPE_QUERY_AUTH_* keys
  are required when read-auth is enabled)"}`; `unreadable_exit=2` with
  `reason":"read-auth secret_file /auth/absent-secret is unreadable: entity not
  found"`. No `listener_bound` in either case; the secret sentinel never
  appeared in the refusal output.
- Method: `harness/run-query-api.sh` builds the `Dockerfile.query-api` image
  from the HEAD snapshot; the runner boots it twice with the two broken
  configs, asserts the exit code, the structured event + reason via `jq`, the
  absence of a bound listener, and the absence of any secret byte.

## Evidence

- [`evidence/QA01.stdout.txt`](evidence/QA01.stdout.txt) — `partial_exit` /
  `unreadable_exit`.
- [`evidence/partial.stderr.txt`](evidence/partial.stderr.txt),
  [`evidence/unreadable.stderr.txt`](evidence/unreadable.stderr.txt) —
  structured `config_validation_failed` events.

## Notes

`.no-compose`: QA01 only boots `query-api` (no gateway / compose stack). The
companion QA02 verifies that when the read-auth config is *valid*, the deployed
binary actually ENFORCES per-request bearer auth.
