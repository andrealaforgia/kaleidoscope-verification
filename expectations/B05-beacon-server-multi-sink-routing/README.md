# B05 — beacon-server-multi-sink-routing

## Surface

Beacon (`beacon-server`), multi-sink fan-out (ADR-0035, Slice 04).
Operator-facing. Reuses the B02 Beacon harness.

## Behaviour

Given a rule that declares two webhook sinks at distinct endpoints and an
Active condition
When beacon-server fires the rule
Then the same Firing incident is POSTed to BOTH sink endpoints — each
incident fans out to every configured sink.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`894cc51`). GREEN — the
  path-recording mock captured the Firing incident at both endpoints:
  ```
  {"path":"/hook-a","name":"b05-multi-sink","resolved":null}
  {"path":"/hook-b","name":"b05-multi-sink","resolved":null}
  ```
- Method: self-contained (`.no-compose`). beacon-server + a mock that
  serves the Active instant query and records `{path, body}` per POST, on
  a throwaway docker network. The rule configures
  `url=.../hook-a` and `url=.../hook-b`; the runner asserts the Firing
  incident landed at both.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `894cc51`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — both
  deliveries (path-tagged).
- [`rules/rule.toml`](rules/rule.toml), [`mock/server.py`](mock/server.py).

## Source

- `crates/beacon-server/src/main.rs:264-266`: for each emitted incident,
  `for sink in &sinks { sink.emit(&incident) }` — every configured sink
  receives it.
- `crates/beacon-server/src/lib.rs` (`build_sinks`) builds one adapter per
  `[[rules.sinks]]` entry.

## Notes

Slice 04 also ships SMTP, Mattermost, Zulip and Grafana OnCall sinks plus
a Transient (5xx, retried) vs Permanent (4xx, stderr diagnostic) delivery
classification (ADR-0035). Those need their own protocol servers / failure
injection and are NOT pinned here; the webhook fan-out is the
black-box-reachable core of the multi-sink contract. The
Transient/Permanent classification is exercised by
`crates/beacon/tests/` and `crates/beacon-server/tests/` and credited
there. Pairs with B04 (inhibition), which also routes through the sink
path.
