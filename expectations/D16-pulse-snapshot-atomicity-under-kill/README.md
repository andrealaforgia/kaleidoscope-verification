# D16 — pulse-snapshot-atomicity-under-kill

## Surface

`pulse-crash-target --seed-then-loop-snapshot`. Per-store instance of
the D09 SNAPSHOT ATOMICITY pattern for the Pulse (metrics) store. Durability
set (#17). Black-box ground for
[issue 007](../../issues/007-non-atomic-snapshot-write-can-brick-the-store.md).

## Behaviour

Given a metric sample seeded as one acked datum (the crash-target prints
`CRASH_TARGET_READY` only after it is durable) and the process then loops
writing snapshots
When the process is SIGKILLed during the snapshot loop and the data dir
is inspected on disk
Then the canonical `store.snapshot` is whole (parses as JSON) or absent,
never a torn/half-written file; and the seeded datum is still present in
durable on-disk state (snapshot or WAL).

## Why atomic-write, and what the kill proves

Each snapshot is written atomically (ADR-0060 §2): serialise to
`store.snapshot.tmp`, fsync, rename onto `store.snapshot` (atomic on
POSIX), fsync the parent dir. The rename is the commit point, so the
canonical path is whole-or-absent across a crash at any instant; a stray
`.tmp` is never read on reopen. Because the rename precedes the WAL
truncate, the single seeded datum is always held wholly by at least one
of WAL or snapshot — never neither. This is the structural answer to
issue 007's "File::create with no temp+rename = total loss on a mid-snapshot
crash"; the store now uses `wal_recovery::atomic_write_snapshot`. Full
rationale in [D09](../D09-lumen-snapshot-atomicity-under-kill/README.md).

## Scope honesty

The assertion is store-schema-agnostic: canonical snapshot whole-or-absent
(`jq` parse) plus "the one seeded datum survived" (some non-empty array in
the snapshot, or a non-empty WAL line). It does not reopen through a read
API (the crash-target ships no read mode); the datum is verified directly
on disk, which is a tighter check than a reopen. `tmp_at_kill` is recorded
honestly: catching a `.tmp` mid-flight is luck (sub-ms window) and the
whole-or-absent invariant does not depend on it.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`a812193`). GREEN — see
  `evidence/D16.stdout.txt` for `snapshot_whole`, `snapshot_present`,
  `record_in_snapshot`/`record_in_wal`, `tmp_at_kill`.
- Method: `harness/assert-snapshot-atomicity.sh` →
  `harness/run-crash-target.sh` builds `pulse-crash-target` from the
  HEAD snapshot, runs `--seed-then-loop-snapshot` detached, waits for
  `CRASH_TARGET_READY`, `docker kill -s KILL`s mid-loop, then asserts
  on-disk that `store.snapshot` parses (or is absent) and the datum
  survived.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `a812193`.
- [`evidence/store.snapshot`](evidence/store.snapshot) — canonical snapshot
  frozen at the kill (whole JSON).
- [`evidence/store.wal`](evidence/store.wal),
  [`evidence/data-listing.txt`](evidence/data-listing.txt),
  [`evidence/crash-target.logs`](evidence/crash-target.logs).

## Source

- store-fsync-durability-v0; `crates/pulse/src/bin/pulse_crash_target.rs`
  (`seed_then_loop_snapshot`) delegating snapshot writes to
  `wal_recovery::atomic_write_snapshot`.

## Notes

One of the per-store snapshot-atomicity set (D09 lumen, D15 ray, D16
pulse, D17 strata, D18 cinder, D19 sluice, D20 beacon). All non-lumen
stores seed a fixed internal datum (no `--body`), so each shares
`harness/assert-snapshot-atomicity.sh`. With D08/D10-D14 (fsync refusal)
this completes the two-axis durability proof across every store.
