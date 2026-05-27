# G02 — gateway-fsync-probe-refuses-readonly-data

## Surface

`kaleidoscope-gateway` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-gateway` started with a `:ro` (read-only)
`/data` mount refuses startup: the Earned-Trust fsync probe
(commit `5ccf4a9`, ADR-0049 §1) tries to write a sentinel and
fsync it; the read-only filesystem returns EROFS; the binary
returns a `PersistenceFailed` error and exits non-zero before
any listener binds.

This is the operator-visible signal that the storage
substrate is genuinely durable-capable, not just `open(2)`-
readable. The contract anchors the durability tightening
landed at commit `5ccf4a9` in response to N20.

## Source

- External contract anchor: commit `5ccf4a9`
  ("feat(earned-trust): honour fsync at pulse write path and
  gateway startup"). ADR-0049 §1 mandates the fsync probe.
- Code: `crates/pulse/src/fsync_probe.rs::probe_or_refuse` +
  `crates/kaleidoscope-gateway/src/main.rs` (the `if let Err(e)
  = probe_or_refuse(&sink, &pulse_path, &fsync_backend).await`
  arm).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-27 UTC at HEAD (`74920c7`).
- Method: `harness/run-gateway.sh` builds the gateway image
  from the snapshot's `Dockerfile.gateway`, then `docker run`
  with `-v "$DATA_HOST:/data:ro"` so the fsync probe must
  fail. Assert exit non-zero AND stderr names the
  fsync/read-only/substrate diagnostic.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/G02.stdout.txt`](evidence/G02.stdout.txt) — runner trace.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt) — observed `Error: PersistenceFailed { reason: "io: Read-only file system (os error 30)" }`.

## Issues

- [issue 005](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)
  — the gateway emits `tracing::error!(event="health.startup.refused", substrate=...)`
  per ADR-0049 §7 but the subscriber is not yet up when this
  fires. The catalogue asserts on the operator-visible `Err(_)`
  printed by default-main instead; tighten this assertion when
  the subscriber lands.

## Notes

`.no-compose` marker — gateway is the system under test,
not a downstream component.

The runner does NOT assert the substrate descriptor shape
because issue 005 means it never reaches stderr; the
`PersistenceFailed { reason: ... }` text from the default
Result-from-main printer is what's currently observable.

This is the second G-prefix contract. G01 covers the
happy-path startup smoke; G02 covers the fsync-honesty
refusal. Together they pin the Earned-Trust posture at v0.
