# 006 — a torn WAL trailing line blocks recovery of ALL intact prior records

- Status: `open`
- Severity: medium (durability robustness; safe-but-brittle)
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
