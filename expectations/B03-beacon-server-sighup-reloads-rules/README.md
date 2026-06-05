# B03 — beacon-server-sighup-reloads-rules

## Surface

Beacon (`beacon-server`), SIGHUP rule-catalogue hot-reload (ADR-0063).
Operator-facing. Reuses the B02 Beacon harness. Resolves
[issue 010](../../issues/010-beacon-sighup-reload-claimed-but-absent.md).

## Behaviour

Given beacon-server is running with a rule catalogue
When the rules directory is edited (a rule added) and SIGHUP is delivered
Then the new catalogue takes effect without a restart: the added rule
starts ticking and firing, the process keeps running, and beacon emits
`event=beacon.reload.succeeded` with the new counts. A reload that finds a
broken or empty catalogue is refused and the previous catalogue is kept
(`beacon.reload.refused`), so a bad edit never takes the alerting engine
dark.

## History — this expectation flipped

Authored RED at `be893c5` to ground issue 010: the docs promised SIGHUP
hot-reload but beacon-server installed no SIGHUP handler, so SIGHUP was a
silent no-op (it survived only because it ran as PID 1). The implementer
accepted the finding and chose to IMPLEMENT rather than doc-fix
(`beacon-sighup-reload-v0`, feat `d9f88ba`, atomic all-or-nothing reload).
B03 was written transition-proof (the A17 pattern) and flipped GREEN on
the DELIVER with no rewrite.

Worth recording: the handler was uncommitted work-in-progress at the
DISTILL SHA `15533b2` (it appeared only in the dirty working tree, not in
`git show HEAD:`). The harness builds from `git archive HEAD`, so B03
correctly stayed RED until the feat was COMMITTED at `d9f88ba`.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`d9f88ba`). GREEN: after adding
  `b03-rule-b` to the live rules dir and sending SIGHUP, beacon emitted
  `beacon.reload.succeeded rules_loaded=2 added=1 removed=0`, and BOTH
  `b03-rule-a` (original) and `b03-rule-b` (added) fired at the webhook —
  the added rule began ticking without a restart.
- Method: self-contained (`.no-compose`). beacon-server + the always-Active
  mock on a throwaway docker network; start with rule A, add rule B to the
  live rules dir, `docker kill -s HUP`, assert B begins firing (reload).
  The runner is transition-proof: it asserts the documented reload and
  flips between RED (silent no-op) and GREEN (reload) on behaviour alone.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `d9f88ba`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — A and B both fired.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — the `beacon.reload.succeeded` event.
- [`rules/a.toml`](rules/a.toml), [`rules/b.toml`](rules/b.toml).

## Source

- `crates/beacon-server/src/main.rs` (`SignalKind::hangup()` handler in the
  select loop → `reload(...)`: re-read the rules dir, validate
  (refuse-and-keep-previous on a broken/empty catalogue), atomic swap of
  the task generation + resolver, `beacon.reload.succeeded`). ADR-0063
  (single-orchestrator atomic all-or-nothing reload), feat `d9f88ba`.

## Notes

The catalogue's first `broken`→`satisfied` flip via an IMPLEMENT (vs A17's
flip via a refuse-to-start). Completes the satisfied Beacon set
(B01/B02/B03/B04/B05/B07); B06 (SLO) stays pending as an unreachable
engine. The refuse-and-keep-previous branch (a malformed edit + SIGHUP
keeps the old catalogue, `beacon.reload.refused`) is the natural B03
follow-on, not separately pinned here.
