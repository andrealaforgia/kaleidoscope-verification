# D09 — lumen-snapshot-atomicity-under-kill

## Surface

`lumen-crash-target --seed-then-loop-snapshot`, the out-of-process
affordance store-fsync-durability-v0 ships so the snapshot-atomicity AC
can be exercised black-box. Durability set (#17).

## Behaviour

Given an acked record seeded into the store (the crash-target prints
`CRASH_TARGET_READY` only after that record is durable) and the process
then loops writing snapshots
When the process is SIGKILLed during the snapshot loop and the data dir
is inspected on disk
Then the canonical `store.snapshot` is whole (parses as JSON) or absent,
never a torn/half-written file; and the acked record is still present in
durable on-disk state.

## Why atomic-write, and what the kill proves

Each snapshot is written atomically (ADR-0060 §2): serialise to
`store.snapshot.tmp` in the same directory, fsync the tmp, rename onto
`store.snapshot` (atomic on POSIX), fsync the parent dir. The rename is
the commit point, so the canonical path is whole-or-absent across a crash
at any instant; a stray `.tmp` is never read on reopen. Because the
rename precedes the WAL truncate, the acked record is always held wholly
by at least one of WAL or snapshot — never neither.

## Scope honesty

The AC is "a kill at ANY instant leaves the canonical snapshot
whole-or-absent". D09 SIGKILLs during the snapshot loop and asserts that
invariant on the frozen on-disk state. It does NOT claim to have frozen a
half-written tmp mid-fsync: the tmp window is sub-millisecond and the
host sampler will usually miss it (`tmp_at_kill=no` is recorded honestly
in evidence). The invariant does not depend on catching the tmp; whole-
or-absent must hold whenever the kill lands, and that is what is checked.

Reopen-and-serve through a read API is not used here: the acked datum is
verified directly on disk (parsed out of the snapshot or WAL host-side),
which is a tighter check than a reopen and needs no reader binary.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-04 UTC at HEAD (`26ff0b6`). GREEN:
  `ready=yes`, `snapshot_present=yes`, `snapshot_whole=yes`,
  `acked_in_snapshot=yes`, `acked_in_wal=no` (the first snapshot migrated
  the record out of the WAL and truncated it; the snapshot is whole).
- Method: `harness/run-crash-target.sh` builds `lumen-crash-target`, runs
  `--seed-then-loop-snapshot --body d09-acked-kal` detached, waits for
  `CRASH_TARGET_READY`, `docker kill -s KILL`s mid-loop, then asserts
  host-side that `store.snapshot` parses (or is absent) and the body is
  present in snapshot or WAL.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `26ff0b6`.
- [`evidence/store.snapshot`](evidence/store.snapshot) — the canonical
  snapshot frozen at the kill (whole JSON).
- [`evidence/store.wal`](evidence/store.wal),
  [`evidence/data-listing.txt`](evidence/data-listing.txt),
  [`evidence/crash-target.logs`](evidence/crash-target.logs).

## Source

- store-fsync-durability-v0; `crates/lumen/src/file_backed.rs:166`
  (`snapshot`) delegating to `wal_recovery::atomic_write_snapshot`
  (`crates/wal-recovery/src/lib.rs`). Crash-target at
  `crates/lumen/src/bin/lumen_crash_target.rs:91`
  (`seed_then_loop_snapshot`).

## Notes

Paired with [D08](../D08-lumen-fsync-refusal-lying-substrate/README.md):
D08 is the WAL-fsync REFUSAL observable, D09 the SNAPSHOT-ATOMICITY
observable. Together they black-box the two halves of the durability AC
the implementer handed off in message 018. The same crash-target affordance
exists on the other six stores for cheap per-pillar extension.
