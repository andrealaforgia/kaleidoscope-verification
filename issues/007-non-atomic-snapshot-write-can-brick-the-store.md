# 007 — non-atomic snapshot write: a crash mid-snapshot bricks the store (total loss)

- Status: `resolved` (2026-06-05). store-fsync-durability-v0 rewired every
  store's snapshot onto `wal_recovery::atomic_write_snapshot`
  (tmp + fsync + rename + fsync-dir, ADR-0060 §2), so a mid-snapshot crash
  leaves the canonical `store.snapshot` whole-or-absent, never torn. Now
  BLACK-BOX REACHABLE (the `<store>-crash-target --seed-then-loop-snapshot`
  binaries loop snapshots, closing the "snapshot not auto-triggered" gap)
  and verified across all seven stores: **D09** lumen + **D15-D20** ray /
  pulse / strata / cinder / sluice / beacon. Each: SIGKILL mid-snapshot →
  canonical snapshot parses whole (or absent) and the acked datum
  survives; several runs froze a `.tmp` in flight while the canonical
  stayed whole. See "Catalogue status".
- Severity: high (durability; total data loss, affects ALL five stores
  including Pulse)
- Surface: lumen / ray / strata / cinder / pulse `FileBacked*Store`
- Opened: 2026-06-02
- Source: `~/dev/kaleidoscope-4-quadrants-theory/kaleidoscope-four-quadrants-report.md`,
  Q2 finding 2.

## The finding (code-read, from the report)

Every store writes its snapshot with `File::create(path)` straight onto
the canonical path, then serialises in place — no temp-file + `rename`
anywhere. `lumen/src/file_backed.rs:164`, `pulse/src/file_backed.rs:259`,
and identically in ray/strata/cinder. A crash midway through writing the
snapshot leaves a TRUNCATED file at the exact path the next `open`
reads; `serde_json` then fails and the whole store refuses to open.

This is TOTAL data loss, not partial. It defeats even Pulse's otherwise
correct fsync discipline, because the file Pulse fsyncs is itself torn.
The standard fix is the durable-rename dance: write to `<path>.tmp`,
fsync the tmp file, `rename` it onto the canonical path, fsync the
parent directory.

## Relation to issue 006

issue 006 is the same class of fault on the WAL's TORN TRAILING LINE
(verified black-box by D04 on lumen). This issue 007 is the SNAPSHOT
file — a different file, a worse blast radius (the snapshot is the whole
state, so a torn snapshot loses everything, whereas a torn WAL tail at
least has the prior snapshot/WAL prefix). Both are "the store cannot
reopen its own on-disk state after an abrupt death".

## Catalogue status

RESOLVED black-box. The reachability gap is closed: store-fsync-durability-v0
ships a `<store>-crash-target --seed-then-loop-snapshot` binary per store
that seeds one acked datum, signals `CRASH_TARGET_READY` once it is
durable, then loops writing snapshots — so a SIGKILL lands mid-snapshot
without needing an admin trigger. D09 (lumen) and D15-D20
(ray/pulse/strata/cinder/sluice/beacon) drive exactly that and assert,
on-disk, that the canonical `store.snapshot` is whole-or-absent (`jq`
parse) and the seeded datum survives in snapshot or WAL. All GREEN at
`a812193`. The original `File::create`-no-rename finding no longer holds
against running behaviour; snapshot writes go through
`wal_recovery::atomic_write_snapshot`.

## The expectation

The observable contract: a store whose snapshot write was interrupted
mid-flight must still reopen and serve the prior durable state (a crash
during a snapshot must not lose acknowledged data). Not yet black-box
reachable here (snapshot is not auto-triggered). How the store achieves
that is the implementer's call; this issue states only the
observed-vs-expected behaviour, sourced from the report's code read.
