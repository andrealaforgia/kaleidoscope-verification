# A24 — aperture-toml-configured-cap-honoured

## Surface

`crates/aperture` config loading (`config/mod.rs` `into_config`) +
HTTP OTLP ingest, after aperture-body-size-cap-v0 (deliver `7313f0b`) and the
unset-default fix `88ef2aa`.

## Behaviour

aperture-body-size-cap-v0 exists to wire the previously **disclosed-but-unwired**
`max_recv_msg_size` knob. ADR-0073 is explicit:

- Earned-Trust note (line 8): "the four-quadrants Q3 report flagged
  `max_recv_msg_size` as a DISCLOSED-but-unwired knob: an operator who sets it,
  expecting OOM protection, gets none."
- Decision (line 67): "`into_config` reads the value from the gRPC arm when set
  ... **exactly as concurrency does**."
- Consequences (line 121): "The disclosed-but-unwired `max_recv_msg_size` knob
  now delivers the OOM protection an operator assumes."

A24 asserts that observable contract: a `max_recv_msg_size` set in the TOML
config is **honoured** on the HTTP ingest path.

## Source

- ADR-0073 lines 8, 67, 121 (above) — the feature's own design decision and
  claimed outcome, asserted as observable behaviour.
- Found by the verifier attacking the deliverable against its ADR (not flagged
  by the implementer): `into_config` (`config/mod.rs:645+`) wires
  `max_concurrent_requests` from the gRPC arm but never calls
  `.max_recv_msg_size()`.

## Verification

- Status: `broken` (transition-proof RED).
- Grounded RED: 2026-06-08 UTC at HEAD (`1f60ff5`).
- Method: build aperture from the HEAD snapshot; boot with a complete valid
  ingest-auth config that **sets `max_recv_msg_size = 16384` (16 KiB)** in both
  `[aperture.transport.{grpc,http}]` arms (the ADR-0073 line-67 location), stub
  sink; mint a valid HS256 bearer; POST `/v1/logs` with `Content-Type:
  application/x-protobuf`.
  - Control `1 KiB` body → `400` (auth + content-type clear; under cap).
  - `100 KiB` body (over the 16 KiB configured cap, under the 2 MiB framework
    default) → **`400`** — accepted past the size gate. Expected for GREEN:
    `413`. A 413 here could come ONLY from the configured cap (100 KiB is well
    under the 2 MiB default), so `400` proves the configured cap is ignored.
- The aperture container starts cleanly with this config (the per-transport
  `max_recv_msg_size` is a valid `TransportArm` field), so this is not a parse
  rejection — the value is parsed and then dropped on the floor.

## Evidence

- [`evidence/codes.txt`](evidence/codes.txt) — `body_1KB=400`,
  `body_100KB=400` at `1f60ff5`.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — no
  `body_too_large` event (the configured-cap path never engages).

## Issues

[014](../../issues/014-aperture-toml-max-recv-msg-size-not-wired.md) — a
TOML-configured `max_recv_msg_size` is not wired by `into_config`, so it is
ignored; only the hardcoded 2 MiB default (A23) applies on any TOML deployment.
The cap is reachable solely via `Config::builder()` (in-process slice_11
tests). This leaves the feature's central promise (ADR-0073 line 121) unmet on
the only operator-reachable surface.

## Notes

`.no-compose`, A22/A23-style self-contained run. Transition-proof: flips GREEN
when `into_config` wires the cap from the TOML config (e.g. reads the gRPC arm
as ADR-0073 line 67 specifies, mirroring `max_concurrent_requests`), making a
100 KiB body → 413 under a 16 KiB config. Distinct from A23 (the unset/default
path, GREEN since `88ef2aa`): A23 = the default posture, A24 = configurability.
