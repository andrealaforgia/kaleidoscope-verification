# B09 — beacon-sighup-applies-valid-skips-malformed

## Surface

Beacon (`beacon-server`), SIGHUP reload PARTIAL-APPLY path (ADR-0063 + the
DISCUSS domain examples). Operator-facing. The third reload branch:
[B03](../B03-beacon-server-sighup-reloads-rules/README.md) = clean apply,
[B08](../B08-beacon-sighup-refuses-malformed-keeps-previous/README.md) =
full refuse (zero valid), B09 = partial apply + diagnostic. Reuses the B02
harness.

## Behaviour

Given beacon-server is firing rule A
When two files are added to the live rules dir — `b.toml` (a VALID rule B)
and `c.toml` (MALFORMED, an unknown field) — and SIGHUP is delivered
Then the reload SUCCEEDS because at least one valid rule was added: B
starts firing, the malformed `c.toml` is reported as a diagnostic and
SKIPPED (rule C never fires), A keeps firing, and the process stays up. A
typo in one added rule blocks neither the good added rules nor the running
ones — report-and-skip on reload, matching startup (B01).

## Why this matters

The refuse path (B08) is for an edit that adds NOTHING valid; this is the
common real case — an operator adds several rules and one has a typo. The
contract is graceful: apply the good ones, surface the bad one, keep
serving. Refusing the whole reload over one typo would be as bad as
silently dropping rules. The `added=1 diagnostics=1` counts and the
fired-vs-skipped split are the observable proof.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`e650368`). GREEN:
  `beacon.reload.succeeded rules_loaded=2 added=1 removed=0 diagnostics=1`;
  rules `b09-rule-a` and `b09-rule-b` fired at the webhook; `b09-rule-c`
  (malformed) never fired; `running_after_hup=true`.
- Method: self-contained (`.no-compose`). Start with rule A (fires), add
  `b.toml` (valid B) + `c.toml` (malformed) to the live rules dir,
  `docker kill -s HUP`, then assert the success event with `added=1` and a
  diagnostic, that B fired and C did not, and the process is up.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `e650368`.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — `beacon.reload.succeeded ... added=1 ... diagnostics=1`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — A and B fired,
  C absent.
- [`rules/a.toml`](rules/a.toml), [`add/b.toml`](add/b.toml),
  [`add/c.toml`](add/c.toml).

## Source

- `crates/beacon-server/src/main.rs` (`reload`: `has_any_rules()` true →
  per-diagnostic `warn`, then atomic swap; `beacon.reload.succeeded` with
  `added`/`removed`/`diagnostics`). The valid/invalid split lives in
  separate files because the multi-file loader skips a broken FILE but
  loads the valid ones (the per-file report-and-skip from B01/startup).

## Notes

Completes the SIGHUP reload contract: B03 (clean apply), B08 (zero-valid
refuse, keep previous), B09 (partial apply + report-and-skip). With
B01/B02/B04/B05/B07 the Beacon set is fully covered bar B06 (the
unreachable SLO engine). No further beacon expectations are planned —
the operator-facing contract is pinned end to end.
