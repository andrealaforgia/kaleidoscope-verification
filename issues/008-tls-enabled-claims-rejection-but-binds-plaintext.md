# 008 — `tls.enabled=true` claims rejection but binds plaintext (security)

- Status: `open` — now GROUNDED black-box by **A15** (RED at `ea72f1e`):
  `tls.enabled=true` yields a plaintext `/readyz=200` listener with a
  WARN line, not a refusal. Fix `tls-config-reject-v0` (ADR-0061) in
  flight; A15 flips GREEN on its DELIVER. See "Catalogue status".
- Severity: high (security; operator could believe transport encryption
  is enforced when it is not)
- Surface: aperture forwarding sink config.
- Opened: 2026-06-02
- Source: `~/dev/kaleidoscope-4-quadrants-theory/kaleidoscope-four-quadrants-report.md`,
  Q2 finding 10.

## The finding (code-read, from the report)

The in-code comment at `crates/aperture/src/sinks.rs:94` states:
"Plaintext at v0; `tls.enabled=true` is reserved by Slice 07 and the
config validator REJECTS it ahead of this sink." The report finds this
claim is FALSE: enabling `tls.enabled=true` emits one warning and then
binds PLAINTEXT — it is not rejected. An operator who sets
`tls.enabled=true` and reads that comment could believe transport
encryption is enforced when traffic is in fact unencrypted.

This is the security-flavoured member of the report's headline theme
(the prose overstates what the code does). The observable contract at
stake: a config that asks for `tls.enabled=true` must not silently
result in plaintext traffic — the operator must be able to tell from the
binary's behaviour whether transport encryption is in force. The
expectation to pin asserts the OBSERVED behaviour against that claim;
remediation is the implementer's call.

## Catalogue status

Not yet black-box re-verified. A G-prefix or A-prefix expectation can
drive this: build an aperture/gateway config with the forwarding sink's
`tls.enabled=true`, start the binary, and assert the OBSERVABLE — does
it refuse with a config error (the documented contract) or start and
bind plaintext (the actual behaviour)? Whichever it does, the
expectation pins it and catches the divergence from the comment. This
needs the exact config field path (the config structs use
`#[serde(deny_unknown_fields)]`, so the toml must be precise); building
that fixture is the next step. Flagged to the implementer.

## Black-box ground (A15, 2026-06-04, HEAD `ea72f1e`)

The fixture landed. `aperture --config` with `[aperture.security.tls]
enabled = true` (stub sink, unique high ports, built standalone from the
HEAD snapshot) was observed: `readyz_plaintext=200`, `running=true`,
`exitcode=0`, and stderr carried
`event=tls_not_supported_in_v0 reason="aperture v0 ships plaintext only;
ignoring tls.enabled=true"`. So the binary answers `/readyz` over plain
HTTP while the operator asked for TLS — the comment's "rejects it" is
false against running behaviour, confirmed black-box, not only by code
read. A15 is recorded `broken` (RED) and is the regression guard.

The implementer (message 019) confirmed the same field path and is
grounding `tls-config-reject-v0` (ADR-0061): aperture will REFUSE TO
START on `tls.enabled` / `auth.spiffe.enabled`, exit non-zero, emit a
refusal event, bind no listener. A15's runner already classifies that
refusal branch, so it flips to `satisfied` on the DELIVER SHA with no
rewrite; the broad refusal-event grep tightens onto the exact event
name/fields she sends then.

## Why it matters to the catalogue

A claim about observable behaviour ("config rejects tls.enabled") that
is false is exactly the kind of thing EDD exists to catch. Once the
fixture lands, this becomes a satisfied expectation asserting the TRUE
behaviour, and a regression guard if the behaviour later changes without
the comment changing (or vice versa).
