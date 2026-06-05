# B01 — beacon-server-boots-with-rules

## Surface

Beacon (`beacon-server`), the alerting engine. Operator-facing. Reuses
the Beacon harness built for B02 (#18, known-gaps N10).

## Behaviour

Given a rules dir with one well-formed rule (`good.toml`) and one
malformed rule (`bad.toml`, an unknown field `frequency`)
When beacon-server is started against it
Then it loads the well-formed rule (`rules_loaded=1`), surfaces the
malformed rule as a diagnostic on stderr (`diagnostics=1`, naming the
unknown field) WITHOUT refusing to start, and stays running. A malformed
rule is reported and skipped, not fatal — the good rule still schedules.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`894cc51`). GREEN:
  `running=true`, stderr carries `rule load diagnostic
  diagnostic=/rules/bad.toml: ... unknown field \`frequency\`` and
  `beacon-server starting rules_loaded=1 diagnostics=1`.
- Method: self-contained (`.no-compose`). Builds beacon-server from the
  HEAD snapshot (`harness/Dockerfile.beacon-server`), runs it against a
  writable temp rules dir (good + bad rule) with a dead `--backend` URL
  (B01 is about boot+load; poll failures are per-tick and non-fatal),
  waits, and asserts the diagnostic, the load counts, and that the
  container is still running. `NO_COLOR=1` + an ANSI strip keep the
  stderr assertions clean.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `894cc51`.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — the diagnostic + the starting line.
- [`evidence/observation.txt`](evidence/observation.txt) — running/exit.
- [`rules/good.toml`](rules/good.toml), [`rules/bad.toml`](rules/bad.toml).

## Source

- `crates/beacon-server/src/main.rs:65-91`: `load_rules` →
  per-diagnostic `warn!("rule load diagnostic")` → if no rules
  `error!("no rules loaded; refusing to start")` exit 1, else
  `info!("beacon-server starting" rules_loaded= diagnostics=)`.
- `crates/beacon/src/loader.rs`: defensive multi-file TOML loader; a
  single broken rule is reported and skipped (`deny_unknown_fields` +
  a "did you mean" suggestion).
- External anchor: `docs/feature/beacon-v0/slices/slice-01-walking-skeleton.md`.

## Notes

The negative control (a rules dir with ONLY malformed rules → `no rules
loaded; refusing to start`, exit 1) is the fail-closed complement; not
separately pinned. Pairs with
[B02](../B02-beacon-server-fires-incident-on-active-condition/README.md)
(fires+resolves). B03 (SIGHUP reload), B04 (inhibition), B05 (multi-sink),
B06 (SLO MWMBR) reuse the same harness.
