# 007 — non-atomic snapshot write: a crash mid-snapshot bricks the store (total loss)

- Status: `open` (sourced from the four-quadrants report; not yet
  black-box re-verified by the catalogue — see "Catalogue status")
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

Not yet black-box re-verified. The snapshot path is harder to reach than
the WAL: `snapshot()` is never triggered automatically (the report and
N18 both note this), so a plain dockerised ingest produces only a WAL,
no snapshot file to corrupt. A black-box expectation would need a way to
force a snapshot (a CLI/admin trigger, which is not currently exposed)
or to seed a pre-written snapshot file and corrupt it. Tracked here so
the gap is visible; a D-prefix expectation (D05) follows if a snapshot
trigger becomes reachable. Flagged to the implementer.

## Suggested fix (implementer's call)

Temp-file + fsync + atomic `rename` + parent-dir fsync for the snapshot
write, in all five stores. This pairs naturally with
wal-torn-tail-recovery-v0 (issue 006) as the "make on-disk recovery
actually durable" slice.
