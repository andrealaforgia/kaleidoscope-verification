# B08 — beacon-sighup-refuses-malformed-keeps-previous

## Surface

Beacon (`beacon-server`), SIGHUP reload REFUSE path (ADR-0063 + the
DISCUSS domain examples). Operator-facing. Reuses the B02 harness. The
safety half of the reload contract; [B03](../B03-beacon-server-sighup-reloads-rules/README.md)
pins the apply half.

## Behaviour

Given beacon-server is firing rule A
When the only rule file is CORRUPTED so a re-read yields zero valid rules,
and SIGHUP is delivered
Then beacon emits `beacon.reload.refused` (`previous_catalogue_retained=true`,
naming the offending file + parse error), keeps the previous catalogue
live (A still firing, EXACTLY ONE incident — no re-page, state kept by
name), and the process stays running. A bad edit does not take the
alerting engine dark.

## Why this matters

The dangerous failure mode for a hot-reload is a typo that silently
disables alerting. beacon refuses-and-keeps-previous instead: a reload
that does not improve on the live catalogue (here, zero valid rules) is
rejected, the running rules keep evaluating, and the operator gets a
structured `beacon.reload.refused` rather than silence or a crash. The
"exactly one incident" assertion is load-bearing: it proves A was NOT
restarted (no duplicate page) and its firing state survived the refused
reload.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`75e6ac8`). GREEN:
  `beacon.reload.refused ... file=/rules/a.toml error=... TOML parse error
  ... previous_catalogue_retained=true`; exactly one `b08-rule-a` firing
  incident (none resolved); `running_after_hup=true`; no
  `beacon.reload.succeeded`.
- Method: self-contained (`.no-compose`). Start with a valid rule A
  (fires), overwrite its file with a rule carrying an unknown field (so a
  re-read loads zero valid rules), `docker kill -s HUP`, then assert the
  refusal event, that A kept its single firing, and the process is up.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `75e6ac8`.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — the `beacon.reload.refused` event.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — one A firing.
- [`evidence/observation.txt`](evidence/observation.txt) — running after HUP.

## Source

- `crates/beacon-server/src/main.rs` (`reload`: re-read → if
  `!has_any_rules()` warn `beacon.reload.refused`
  (`previous_catalogue_retained=true`) and RETURN without swapping; the
  old task generation + resolver stay live). ADR-0063 + the DISCUSS domain
  examples (the implementer followed the examples over a looser ADR
  phrasing — message 022).

## Notes

Completes the SIGHUP reload contract with B03 (apply path). The
implementer made the negatives first-class (message 022): refuse on zero
valid rules OR a parse edit that adds no valid rule; apply + per-file
diagnostic when at least one valid rule loads; state kept by name across
both. B08 pins the zero-valid refuse; the partly-broken-but-adds-valid
apply-with-diagnostic case is credited to her DISTILL acceptance suite.
