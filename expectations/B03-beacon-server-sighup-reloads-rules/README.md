# B03 — beacon-server-sighup-reloads-rules

## Surface

Beacon (`beacon-server`), SIGHUP rule-catalogue hot-reload. Operator-facing.
Reuses the B02 Beacon harness. Grounds
[issue 010](../../issues/010-beacon-sighup-reload-claimed-but-absent.md).

## Behaviour (documented contract under test)

Given beacon-server is running with a rule catalogue
When the rules directory is edited and SIGHUP is delivered
Then the new catalogue takes effect without a restart: added rules start
ticking, removed rules stop. (Docs: c4-context "loaded on start +
SIGHUP", c4-container "SIGHUP handler triggers Loader reload", slice-02
"SIGHUP triggers reload; the previous catalogue stays active",
wave-decisions [D3].)

## Status: `broken` — RED at HEAD, grounding issue 010

The documented reload is absent. beacon-server installs only SIGINT and
SIGTERM handlers (`main.rs:177-186`); rules are loaded ONCE at startup
(`main.rs:164`) with one task spawned per rule, and there is no SIGHUP
handler. Black-box at `be893c5`: rule A fired; rule B was then added to
the live rules dir and SIGHUP delivered; B NEVER fired and beacon kept
running the original catalogue (`running_after_hup=true`, exit 0, no
reload log). SIGHUP is a SILENT NO-OP — the process neither reloads nor
stops (it runs as PID 1, so the kernel ignores SIGHUP's default-terminate
with no handler installed).

The runner therefore exits non-zero here by design: the documented
contract is violated, and a verifier records the failing expectation.

Transition-proof (the A17 pattern): the runner asserts the documented
reload (the added rule fires after SIGHUP). It flips GREEN automatically
if a SIGHUP reload handler lands. If instead the docs are corrected to
state v0 loads rules only at startup, B03 is re-framed to pin that
load-once behaviour and issue 010 closes as a doc fix.

## Verification

- Status: `broken` (RED, known defect; tracks issue 010)
- Last verified: 2026-06-05 UTC at HEAD (`be893c5`). RED:
  `running_after_hup=true`, only `{"name":"b03-rule-a"}` at the webhook,
  `b03-rule-b` absent, no reload log.
- Method: self-contained (`.no-compose`). beacon-server + the always-Active
  mock on a throwaway docker network; start with rule A, add rule B to the
  live rules dir, `docker kill -s HUP`, then assert whether B begins
  firing (reload) or not (silent no-op).

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `be893c5`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — only A fired.
- [`evidence/observation.txt`](evidence/observation.txt) — running after HUP.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — one `rules_loaded=1` at startup, no reload.
- [`rules/a.toml`](rules/a.toml), [`rules/b.toml`](rules/b.toml).

## Source

- `crates/beacon-server/src/main.rs:164` (load once), `:172` (spawn per
  rule), `:177-186` (SIGINT + SIGTERM only; no SIGHUP). Comment at
  `main.rs:45` says "SIGHUP reload arrives at slice 03" while slice-02 doc
  claims it shipped.

## Notes

The first `broken` Beacon expectation. Pairs with the satisfied B01/B02/
B04/B05. The PID-1 detail matters: under an init/tini, an unhandled
SIGHUP would TERMINATE beacon-server instead of being ignored — arguably
worse for an operator who runs the documented "SIGHUP to reload".
