# D14 — beacon-fsync-refusal-lying-substrate

## Surface

`beacon-crash-target --probe-lying`. Per-store instance of the D08
WAL-fsync REFUSAL pattern for the Beacon (alerting rule-state) store. Durability set (#17).

## Behaviour

Given the beacon composition root is driven against a substrate that
lies about durability (a `LyingFsyncBackend` that acks an fsync which
never reached stable storage)
When `beacon-crash-target --probe-lying` runs
Then the store is refused before it is ever opened for writes: stderr
carries `event=health.startup.refused substrate=<descriptor>`, the
process exits non-zero, and no store payload (`*.wal` / `*.snapshot`)
is written.

## Why this is the fsync AC

A post-ack process kill (D01-D03) proves flush-to-kernel plus WAL replay
but CANNOT distinguish `flush()` from `sync_all()`: the page cache
survives the kill, so the fsync wiring is invisible from outside. The
composition root makes it observable from the other side by REFUSING a
substrate it has proven cannot durably fsync. The fsync-IS-wired
happy-path count stays in-suite (`CountingFsyncBackend`) and is credited
to the implementer, not claimed here. Full rationale in
[D08](../D08-lumen-fsync-refusal-lying-substrate/README.md).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-04 UTC at HEAD (`ea72f1e`). GREEN:
  `probe_exit` non-zero, stderr `event=health.startup.refused
  substrate=fsync-noop`, `payload_written=no`.
- Method: `harness/assert-probe-lying-refusal.sh` →
  `harness/run-crash-target.sh` builds `beacon-crash-target` from the
  HEAD snapshot (`Dockerfile.crash-target`, single codegen unit), runs
  `--probe-lying` with `KALEIDOSCOPE_CRASH_PILLAR_ROOT=/data`, and
  asserts non-zero exit, the refusal event with a `substrate=`
  descriptor, NOT the `fsync-unexpected-pass` branch, and no payload.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `ea72f1e`.
- [`evidence/probe-lying.stderr`](evidence/probe-lying.stderr) — the refusal line.
- [`evidence/data-listing.txt`](evidence/data-listing.txt) — the data dir
  after the refusal (no store payload).

## Source

- store-fsync-durability-v0; `crates/beacon/src/bin/beacon_crash_target.rs`
  (`probe_lying`), emitting `event=health.startup.refused
  substrate=<descriptor>` and a non-zero exit.

## Notes

One of the per-store fsync-refusal set (D08 lumen, D10 ray, D11 strata,
D12 cinder, D13 sluice, D14 beacon). Pulse ships only the snapshot mode
(it historically fsynced), so it has no probe-lying instance. All share
`harness/assert-probe-lying-refusal.sh`.
