# 008 — `tls.enabled=true` claims rejection but binds plaintext (security)

- Status: `open` (sourced from the four-quadrants report; black-box
  expectation to follow — see "Catalogue status")
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
(the prose overstates what the code does). Per the report, the right fix
is to the BEHAVIOUR, not the comment: either actually reject
`tls.enabled=true` at config-validation time (exit 2, config error), or
implement TLS. A silent downgrade to plaintext under a config that asks
for TLS is the dangerous outcome.

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

## Why it matters to the catalogue

A claim about observable behaviour ("config rejects tls.enabled") that
is false is exactly the kind of thing EDD exists to catch. Once the
fixture lands, this becomes a satisfied expectation asserting the TRUE
behaviour, and a regression guard if the behaviour later changes without
the comment changing (or vice versa).
