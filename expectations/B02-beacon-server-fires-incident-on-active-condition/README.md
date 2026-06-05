# B02 — beacon-server-fires-incident-on-active-condition

## Surface

Beacon (`beacon-server`), the alerting engine over any OTel-compatible
PromQL backend. Operator-facing. The first black-box test of the Beacon
surface (#18, known-gaps N10).

## Behaviour

Given a rule whose PromQL query reports the condition Active (a non-empty
instant-query result) and then Inactive (empty)
When beacon-server polls the backend on its interval with a webhook sink
configured
Then it POSTs one Firing incident (the rule name and query, `resolved_at`
null) to the sink on the Active transition, and one Resolved incident
(`resolved_at` set) when the query returns to empty.

## Harness

The design the B0x scaffolds called for, built here. A single mock
container (`mock/server.py`, `python:3-slim`) plays BOTH roles on a
dedicated docker network:

- PromQL instant-query backend: `GET /api/v1/query` returns a non-empty
  vector for the first `FIRING_WINDOW=5s` (drives Active → Firing), then
  an empty vector (drives Active → Inactive → Resolved). beacon only
  checks empty-vs-non-empty, so the threshold lives in the rule PromQL.
- Webhook sink catcher: `POST /hook` appends the raw Incident JSON to
  `incidents.ndjson`.

beacon-server (`--rules /rules --backend http://b02-mock:18091/api/v1`)
runs with `for_duration=0s`, `interval=1s`, so both transitions land
inside a ~10s window. The rules dir is mounted WRITABLE because
beacon persists rule-state at `<rules>/.beacon-state/store` (no separate
CLI flag); a temp copy is used so the repo stays clean.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`894cc51`). GREEN — captured at
  the webhook sink:
  ```
  {"name":"b02-synthetic-up-down","query":"up == 0","resolved_at":null}
  {"name":"b02-synthetic-up-down","query":"up == 0","resolved_at":{"secs_since_epoch":...}}
  ```
  one Firing then one Resolved, exactly one transition each.
- Method: self-contained (`.no-compose`). Builds beacon-server from the
  HEAD snapshot (`harness/Dockerfile.beacon-server`,
  `--build-context kaleidoscope=`), wires mock + beacon on a throwaway
  docker network, asserts a Firing incident (name + query, `resolved_at`
  null) and a Resolved incident (`resolved_at` set).

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `894cc51`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — the two
  captured incidents.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — `rules_loaded=1`, the emit transitions.
- [`mock/server.py`](mock/server.py),
  [`rules/rule.toml`](rules/rule.toml) — the fixture.

## Source

- `crates/beacon-server/src/main.rs` (`--rules`/`--backend`, per-rule
  ticker → fetch → transition → emit), `crates/beacon-server/src/lib.rs`
  (`fetch_query`: empty result → Inactive, non-empty → Active),
  `crates/beacon/src/sinks.rs` (`WebhookSink` POSTs the Incident JSON),
  `crates/beacon/src/types.rs` (`Incident`: firing has `resolved_at`
  null, resolved has it set).
- External anchor: `docs/feature/beacon-v0/slices/slice-01-walking-skeleton.md`.

## Notes

Establishes the reusable beacon harness (`Dockerfile.beacon-server` +
mock-as-backend-and-catcher). B01 (boots with rules), B03 (SIGHUP
reload), B04 (inhibition), B05 (multi-sink), B06 (SLO MWMBR) are the
follow-on expectations that reuse it. Note: query-api serves only
`/api/v1/query_range`, not the instant `/api/v1/query` beacon polls, so a
mock backend (not kaleidoscope's own query-api) drives beacon here;
beacon is backend-agnostic by design ("any OTel-compatible PromQL
backend"), so this is a faithful black-box of beacon's own contract.
