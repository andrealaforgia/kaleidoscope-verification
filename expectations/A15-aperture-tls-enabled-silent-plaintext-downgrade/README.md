# A15 — aperture-tls-enabled-silent-plaintext-downgrade

## Surface

`aperture --config <toml>` with `[aperture.security.tls] enabled = true`.
Operator-facing transport security. The black-box ground for
[issue 008](../../issues/008-tls-enabled-silent-plaintext-downgrade.md).

## Behaviour (contract under test)

Given an operator config that sets `tls.enabled = true`
When aperture is started with that config
Then aperture must NOT serve a plaintext listener: it must either refuse
to start (exit non-zero, emit a refusal naming the unsupported knob, bind
no listener) or actually serve TLS. A plaintext listener answering
`/readyz` over plain HTTP while `tls.enabled=true` is the violation.

## Status: `broken` — RED at HEAD, grounding issue 008

At `ea72f1e` aperture takes the UNSAFE shape: it logs
`event=tls_not_supported_in_v0` (a WARN line an operator may never see)
and binds PLAINTEXT anyway. An operator who set `tls.enabled=true`
believing they get transport encryption silently gets an unencrypted
listener. That is the Earned-Trust violation issue 008 tracks. The
runner therefore exits non-zero here by design: the contract is
violated, and a verifier records a failing expectation rather than
papering over it.

This is transition-proof. tls-config-reject-v0 (ADR-0061) is in flight
to make aperture REFUSE TO START on this knob (discuss/design/devops/
distill landed by `ea72f1e`; the refusal acceptance tests are RED-ready,
the DELIVER green is not yet in). When that lands, this same runner
detects the refusal branch (non-zero exit, no listener, refusal event)
and flips to GREEN automatically — no rewrite. The broad refusal-event
grep tightens onto the exact event name/fields when the implementer
sends the SHA.

## Verification

- Status: `broken` (RED, known defect; tracks issue 008)
- Last verified: 2026-06-04 UTC at HEAD (`ea72f1e`). RED:
  `readyz_plaintext=200`, `running=true`, `exitcode=0`,
  `warn_tls_not_supported=yes`.
- Method: self-contained (`.no-compose`). Builds aperture from the HEAD
  snapshot (`Dockerfile.aperture`, `--build-context kaleidoscope=`), runs
  it on unique high host ports (34318/34317, N27 discipline) with the
  tls-enabled fixture, and classifies: plaintext `/readyz=200` →
  DOWNGRADE (RED); non-zero exit + refusal event + no listener → REFUSAL
  (GREEN). It does NOT use the compose readiness gate, which assumes a
  binding listener and would itself break once aperture starts refusing.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `ea72f1e`.
- [`evidence/observation.txt`](evidence/observation.txt) — the four
  observables.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — the
  `tls_not_supported_in_v0` warn line and the plaintext bind.
- [`aperture-tls-enabled.toml`](aperture-tls-enabled.toml) — the operator
  config that asks for TLS.

## Source

- `crates/aperture/src/config/mod.rs:56` (`tls_enabled` field, parsed
  from `[aperture.security.tls] enabled`).
- `crates/aperture/src/compose.rs:45-75`
  (`warn_if_v0_security_knob_set`): warns then binds plaintext.
- The false comment at `crates/aperture/src/sinks.rs:94` claims a config
  validator rejects this ahead of the sink; it does not (implementer
  message 019).

## Notes

The first `broken` expectation in the catalogue and the first deliberately
RED one: it exists to make issue 008's failing contract observable and to
flip green the moment the fix lands. Negative control (tls.enabled=false
starts normally and binds) is the implicit baseline every other aperture
expectation already exercises.
