# D07 — cinder-torn-wal-tail-recovery

## Surface

kaleidoscope-cli `ingest` + `list-items` over the Cinder tier-metadata
store, under a torn Cinder WAL. Operator-facing durability robustness.
Durability set (#17 / N18), Cinder pillar. The fourth and last pillar of
the issue-006 close (after D04 lumen, D05 ray, D06 pulse).

## Behaviour

Given `kaleidoscope-cli ingest` has written a Cinder Hot placement (one
per batch) into `<data>/cinder.wal`, and that WAL's trailing line is then
TORN (incomplete JSON, no newline)
When `list-items <tenant> <data> hot` reopens the Cinder store
Then it recovers the intact prefix and ignores the torn tail: the
command exits 0 and lists the placement that preceded the torn line.

The runner accepts either SAFE shape (recovery OR clean fail-closed with
a clear `cinder open` error) and fails only on a silent crash or lost
data; at `88d5a3f` the recovery branch fires.

## Source

- wal-torn-tail-recovery-v0 rewired cinder's open onto the shared
  `wal_recovery::replay_wal_tolerating_torn_tail` seam (pillar="cinder"),
  feat `1886d94`.
- The CLI opens Cinder at `<data>/cinder` (`crates/kaleidoscope-cli/src/lib.rs:140`),
  WAL `<data>/cinder.wal`.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-04 UTC at HEAD (`88d5a3f`). GREEN, recovery
  branch: `ingest_exit=0`, `items_before=1`, `listitems_exit=0`,
  `items_after=1` — the Hot placement survived the torn tail.
- Method: `harness/run-kaleidoscope-cli.sh`. `ingest` two records (one
  Hot placement); a baseline `list-items` confirms 1 item; the host-side
  `cinder.wal` gets an incomplete JSON line appended (no newline); a
  second `list-items` reopens Cinder and is asserted to recover.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `88d5a3f`.
- [`evidence/cinder.wal.before`](evidence/cinder.wal.before),
  [`evidence/cinder.wal.after`](evidence/cinder.wal.after) — WAL before/after.
- [`evidence/list-items-after.out`](evidence/list-items-after.out) — the
  recovered placement.

## Issues

The black-box ground truth that settled the cinder thread of
[issue 006](../../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md):
cinder genuinely bricked before its rewire (`1886d94`) and now recovers.
An earlier over-retraction (that cinder "never bricked") was corrected
on the implementer's timestamped evidence + this black-box result.

## Notes

Cinder is reached via the CLI, not a gateway→read-API path, so D07 uses
the K-prefix harness rather than the gateway fixture of D04/D05/D06.
Completes the four-pillar black-box close of issue 006.
