# D08 — lumen-fsync-refusal-lying-substrate

## Surface

`lumen-crash-target --probe-lying`, the out-of-process affordance
store-fsync-durability-v0 ships so the WAL-fsync AC can be exercised
black-box. Durability set (#17). The fsync half of the durability story
that a post-ack process kill cannot reach.

## Behaviour

Given the lumen composition root is driven against a substrate that lies
about durability (a `LyingFsyncBackend` that acks an fsync which never
reached stable storage)
When `lumen-crash-target --probe-lying` runs
Then the store is refused before it is ever opened for writes: stderr
carries `event=health.startup.refused substrate=<descriptor>`, the
process exits non-zero, and no store payload is written to the data dir.

The substrate is probed BEFORE the store opens, so no datum is ever
acked against a substrate proven to lie.

## Why this is the fsync AC, and D01-D03 are not

D01/D02/D03 SIGKILL the gateway after an ack and assert the acked datum
survives reopen. They prove flush-to-kernel plus WAL replay, but they
CANNOT distinguish `flush()` from `sync_all()`: the page cache survives a
process kill, so a store that only flushed looks identical to one that
fsynced. The fsync wiring is therefore invisible to a process kill. D08
makes it observable from the other side: the composition root REFUSES a
substrate it has proven cannot durably fsync. That refusal is the
externally observable consequence of the fsync probe being wired.

The complementary "fsync is actually called on the happy path" count is
in-suite only (a `CountingFsyncBackend` that the implementer's tests
assert on); it is not black-box reachable for the same page-cache reason,
and is credited to her in-suite probe.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-04 UTC at HEAD (`26ff0b6`). GREEN:
  `probe_exit=1`, stderr `event=health.startup.refused
  substrate=fsync-noop`, `wal_present=no`.
- Method: `harness/run-crash-target.sh` builds `lumen-crash-target` from
  the HEAD snapshot (`harness/Dockerfile.crash-target`, single codegen
  unit per the issue-004 OOM lesson), runs `--probe-lying` with
  `KALEIDOSCOPE_CRASH_PILLAR_ROOT=/data`, asserts non-zero exit, the
  refusal event with a `substrate=` descriptor, NOT the
  `fsync-unexpected-pass` branch, and that no WAL was written.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `26ff0b6`.
- [`evidence/probe-lying.stderr`](evidence/probe-lying.stderr) — the
  refusal line.
- [`evidence/data-listing.txt`](evidence/data-listing.txt) — the data dir
  after the refusal (no store payload).

## Source

- store-fsync-durability-v0 wired each store's composition root to probe
  the fsync substrate before opening for writes; lumen's `--probe-lying`
  refusal is assertable at `9d7446d` (implementer messages 017/018).
- `crates/lumen/src/bin/lumen_crash_target.rs:122` (`probe_lying`),
  emitting `event=health.startup.refused substrate=<descriptor>` and
  `ExitCode::FAILURE`.

## Notes

First of the per-pillar fsync-refusal set. The same `--probe-lying`
affordance exists on `ray`, `pulse`, `strata`, `cinder`, `sluice`, and
`beacon` crash-targets; D08 is the lumen instance, parametrised by the
shared `run-crash-target.sh` driver so the others are cheap to add.
