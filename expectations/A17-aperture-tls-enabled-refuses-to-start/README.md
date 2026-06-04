# A17 — aperture-tls-enabled-refuses-to-start

## Surface

`aperture --config <toml>` with `[aperture.security.tls] enabled = true`.
Operator-facing transport security. Resolves
[issue 008](../../issues/008-tls-enabled-claims-rejection-but-binds-plaintext.md).

## Behaviour

Given an operator config that sets `tls.enabled = true`
When aperture is started with that config
Then aperture REFUSES TO START: config validation fails before any
`Config` is built (so the bind path is never entered), stderr carries
`event=config_validation_failed` naming the unsupported knob, the process
exits 2, and no listener binds (connect-refused on 4317 and 4318).

Negative control: `tls.enabled = false` (or absent) starts and binds
normally with no refusal event — the baseline every other aperture
expectation already exercises.

## History — this expectation flipped

Authored RED at `ea72f1e` to ground issue 008: at that SHA aperture
logged `event=tls_not_supported_in_v0` and bound PLAINTEXT anyway, a
silent downgrade for an operator who asked for transport encryption. The
fix `tls-config-reject-v0` (ADR-0061, feat `a56c317`) deleted the
warn-and-bind path and made aperture refuse. A17 was written so the same
runner detects both shapes, and it flipped GREEN automatically on the
DELIVER.

The refusal is on the CONFIG-VALIDATION axis, distinct from the
substrate-lied axis (`health.startup.refused`, the D08/D10-D14 fsync
probe). The implementer corrected the event name to
`config_validation_failed` in message 020; A17's grep is pinned to it.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`a812193`). GREEN:
  `readyz_plaintext=000` (connect-refused), `running=false`,
  `exitcode=2`, `config_validation_failed=yes`, `names_tls_enabled=yes`,
  `warn_tls_not_supported=no` (the old warn-and-bind line is gone).
- Method: self-contained (`.no-compose`). Builds aperture from the HEAD
  snapshot (`Dockerfile.aperture`, `--build-context kaleidoscope=`), runs
  it on unique high host ports (34318/34317, N27) with the tls-enabled
  fixture, and classifies: plaintext `/readyz=200` → DOWNGRADE (RED, the
  old defect); non-zero exit + `event=config_validation_failed` naming
  `tls.enabled` + no listener → REFUSAL (GREEN). It does NOT use the
  compose readiness gate, which assumes a binding listener and would
  itself break against a refusing aperture.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `a812193`.
- [`evidence/observation.txt`](evidence/observation.txt) — the six observables.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — the
  `config_validation_failed` line naming `tls.enabled`.
- [`aperture-tls-enabled.toml`](aperture-tls-enabled.toml) — the operator
  config that asks for TLS.

## Source

- `tls-config-reject-v0`, feat `a56c317`: refusal in
  `RawConfig::into_config` (returns `Err` before any `Config` is built),
  so the no-plaintext-bind guarantee is structural, not ordering. ADR-0061
  supersedes the ADR-0008 warn-and-ignore for this knob.
- The schema knobs (`tls.enabled`, `auth.spiffe.enabled`, `cert_path`, …)
  remain in the config, default off (ADR-0008 forward-compat preserved);
  only the `=true` runtime reaction flipped from warn-and-bind to refuse.

## Notes

Was the catalogue's first `broken` expectation (deliberate RED grounding
issue 008); now satisfied. Originally mis-numbered A15, which collided
with the pre-existing `A15-config-error-pre-init-exit-two`; renumbered
A17 (A16 is `post-init-lifecycle-via-tracing`). The sibling knob
`auth.spiffe.enabled=true` triggers the same refusal (both named when
both set); not separately pinned.
