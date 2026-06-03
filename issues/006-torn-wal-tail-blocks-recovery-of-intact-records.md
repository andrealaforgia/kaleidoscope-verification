# 006 — a torn WAL trailing line blocks recovery of ALL intact prior records

- Status: `partial` — FIXED + black-box verified for lumen (`87d9363`,
  D04) and ray (`188c6c2`, D05), both on the shared `wal-recovery` seam.
  Cinder is NOT a torn-tail brick (the earlier claim is RETRACTED — see
  the Cinder note below; its doc is accurate and it already recovers).
  pulse to confirm. Closes when the genuinely-affected pillars
  (lumen ✓, ray ✓, + any other that actually bricked) are covered.
- Severity: medium (durability robustness; safe-but-brittle)

## Resolution — lumen (2026-06-03, HEAD 87d9363)

wal-torn-tail-recovery-v0 rewired lumen's `FileBackedLogStore::open`
onto the shared `crates/wal-recovery` seam (feat `87d9363`, after the
seam crate landed at `0eb6227`). Black-box re-verified by **D04** at
`87d9363`: a torn trailing line in `lumen.wal` no longer bricks the
store — log-query-api starts (`running=true`, exit 0), serves the 6
intact records (`query_count=6`), and ignores the torn tail. D04's
pre-coded recovery branch is now the asserted path. ray
(`crates/ray/src/file_backed.rs` was dirty/uncommitted) and cinder were
not yet rewired at this SHA, so the issue stays `partial` until they do.
- Surface: lumen `FileBackedLogStore` (and, by the same code shape, the
  other WAL-backed pillars — ray confirmed identical, pulse likely).
- Expectations affected: D04 (documents the SAFE half of this behaviour
  and stays GREEN; this issue tracks the brittle half).
- Opened: 2026-06-01
- Kaleidoscope SHA at observation: `eef7576`

## Observed

A `FileBackedLogStore` whose WAL (`<pillar_root>/lumen.wal`) ends in a
TORN trailing line — an incomplete JSON record with no newline, exactly
the shape a mid-write crash or power loss leaves — cannot be reopened.
`FileBackedLogStore::open` reads the WAL line by line and runs every
non-empty line through `serde_json::from_str`; the torn final line fails
to parse and `open` returns
`PersistenceFailed { reason: "WAL parse error at line N: EOF while parsing ..." }`.

Black-box, via D04: 6 well-formed records were ingested through the
gateway and the gateway stopped cleanly; one torn partial line was then
appended to `lumen.wal`; log-query-api started against that `/data`:

```
lqapi_running=false  lqapi_exitcode=1
Error: PersistenceFailed { reason: "WAL parse error at line 7: EOF while parsing an object at line 1 column 86" }
```

The service exits 1 and never binds. The 6 intact, acked, durable
records before the torn line become inaccessible through the read path.

## Why this matters

The behaviour is SAFE in one sense and the catalogue records that with a
GREEN expectation (D04): the store does NOT serve corrupt or partial
data; it fails closed with a clear, specific error. Fail-closed on
corruption beats serving garbage.

But it is brittle: a single torn trailing line — the *expected* residue
of an abrupt death, the very scenario the v1 "survives a restart"
durability story is about — renders the whole store unreadable, intact
records and all, with no automatic recovery. An operator's only remedy
is manual WAL surgery (truncate the last line). After a real power loss
that is a sharp edge: the durable data is on disk and intact, but the
service refuses to start.

## Expected / options (implementer's call)

This may be a deliberate v1 limitation rather than a bug, so this is a
finding to triage, not a prescription. Reasonable resolutions:

1. On open, tolerate a torn FINAL line: if the last line fails to parse
   AND it is the last line AND it has no trailing newline, treat it as a
   never-completed write, drop it (optionally truncate the file to the
   last good newline), recover the intact prefix, and log a warning.
   This is the standard WAL recovery convention.
2. Keep failing closed, but document the manual recovery step and
   surface it in the error message (e.g. "truncate the final partial
   record to recover").
3. Confirm it is an accepted v1 limitation and document the boundary in
   the durability ADR, so the "survives a restart" claim is scoped to
   *graceful* restart only.

## Reproduction

`./run-expectation.sh D04` (the runner ingests, tears the WAL tail, and
observes the reopen). Evidence under
`expectations/D04-lumen-torn-wal-tail-recovery/evidence/`:
`lumen.wal.before` / `lumen.wal.after`, `log-query-api.stderr.txt`.

## Catalogue impact

D04 stays GREEN against the SAFE invariant (no corrupt data served,
clear error). If option 1 lands, D04's recovery branch (already coded:
running=true → intact records served, torn tail ignored) becomes the
asserted path and this issue closes.

## Cinder note — RETRACTED (per-module report, 2026-06-03)

An earlier note here (from the system-level four-quadrants report) said
Cinder's doc CLAIMS torn-tail tolerance while the code bricks. **That is
withdrawn.** The per-module read
(`~/dev/kaleidoscope-4-quadrants-theory/reports/cinder.md`, Q2) refuted
it: Cinder's `open` delegates to
`wal_recovery::replay_wal_tolerating_torn_tail` and recovers the intact
prefix correctly (`crates/cinder/src/file_backed.rs:152-165`, test
`reopen_recovers_the_intact_prefix_after_a_torn_tail`); the doc matches
the code. The "proof of bricking" the system report cited
(`corrupted_wal_surfaces_typed_persistence_error_on_open`) appends a
COMPLETE-but-malformed line WITH a trailing newline — a different case
(correctly fail-closed), NOT a torn tail. So Cinder is NOT a torn-tail
brick and its doc is NOT false; this was a first-pass misread, relayed
to Bea Implementer and now corrected (do not "fix" the cinder doc).

This issue 006 stands for the pillars that genuinely bricked: **lumen**
(D04 confirmed bricking at `eef7576`, fixed `87d9363`) and **ray** (D05,
fixed `188c6c2`). Cinder's REAL defects are the shared fsync gap +
non-atomic snapshot ([issue 007](007-non-atomic-snapshot-write-can-brick-the-store.md),
N18) and the swallowed `place`/`evaluate_at` WAL errors (the
implementer's cinder-wal-error-surfacing-v0), NOT the torn tail.

----------------------------------------------------------------
Superseded note (kept for the audit trail; the claim below is WRONG):
----------------------------------------------------------------

So Cinder is the same torn-tail-bricks-recovery defect this issue tracks
(verified black-box on lumen by D04), made worse by a doc that promises
the opposite behaviour. The implementer's accepted fix
(wal-torn-tail-recovery-v0, option 1) should cover lumen, ray, AND
cinder; the cinder doc must be corrected too. The report classes the
doc-vs-code contradiction as a documentation overstatement, which is the
report's headline theme (the prose overstates what the code does).
