# 014 — aperture's TOML-configured max_recv_msg_size is not wired (only the 2 MiB default applies)

- Status: `open` (2026-06-08). Grounded RED by **A24** at kaleidoscope HEAD
  `1f60ff5` (aperture-body-size-cap-v0 + unset-fix `88ef2aa`).
- Severity: medium (the feature's central capability — a configurable ingest
  body cap — is non-functional on the only operator-reachable surface; the
  2 MiB default protection from A23/`88ef2aa` is intact, so this is a
  configurability gap, not an open DoS).
- Surface: `crates/aperture/src/config/mod.rs` `RawConfig::into_config`.
- Opened: 2026-06-08
- Source: found by the verifier attacking aperture-body-size-cap-v0 against its
  own ADR-0073; not flagged by the implementer (msg 033/034 addressed only the
  unset-default regression, issue 013). Distinct facet split out of 013.

## The gap

aperture-body-size-cap-v0 exists to wire the previously disclosed-but-unwired
`max_recv_msg_size` knob. ADR-0073 says so and designs the wiring:

- line 8: "an operator who sets it, expecting OOM protection, gets none" — the
  problem the feature closes.
- line 67: "`into_config` reads the value from the gRPC arm when set ... exactly
  as concurrency does."
- line 121: "The disclosed-but-unwired `max_recv_msg_size` knob now delivers the
  OOM protection an operator assumes."

But `into_config` (`config/mod.rs:645+`) never calls `.max_recv_msg_size()`. It
wires `max_concurrent_requests` from the gRPC arm one line over, but not the
size cap. So the enforced `Config.max_recv_msg_size` is settable ONLY via
`Config::builder().max_recv_msg_size()` — which only the in-process slice_11
tests use. Every TOML-configured aperture (the production + harness deployment)
runs with the cap unset and gets only the hardcoded 2 MiB default (A23).

## Observed (black-box, A24)

aperture booted from a TOML config with `max_recv_msg_size = 16384` (16 KiB) in
both transport arms; valid bearer; `Content-Type: application/x-protobuf`;
POST `/v1/logs`:

| body | result | meaning |
| --- | --- | --- |
| 1 KiB (control) | 400 | auth + content-type clear |
| 100 KiB (over 16 KiB cap, under 2 MiB default) | **400** | configured cap **ignored** (a 413 here could only come from the 16 KiB cap) |

The container starts cleanly (the value parses as a `TransportArm` field), then
the value is dropped — confirming a wiring omission, not a parse rejection. The
in-process slice_11 tests pass because they set the cap via the builder, which
bypasses `into_config` entirely.

## What would make A24 pass

`into_config` wires the configured `max_recv_msg_size` to the enforced cap (e.g.
reads the gRPC arm as ADR-0073 line 67 specifies, mirroring the
`max_concurrent_requests` wiring), so a 16 KiB config refuses a 100 KiB body
(413). The fix shape is the implementer's call; A24 asserts the contract
format-agnostically.

## Scope note (verifier)

Reported as a failing expectation about observable behaviour. This is the
configurability facet only; the unset-default DoS regression (the body is
unbounded with no cap) is the SEPARATE issue 013, fixed by `88ef2aa` and
verified GREEN by A23. The gRPC path is not asserted here (the regression and
this gap were demonstrated on HTTP; tonic's native 4 MiB decode default is the
implementer's stated gRPC-unset posture, not independently attacked).
