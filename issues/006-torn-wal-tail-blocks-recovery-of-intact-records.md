# 006 — a torn WAL trailing line blocks recovery of ALL intact prior records

- Status: `resolved` (2026-06-04). All four WAL-backed pillars reopen and
  serve the intact prefix after a torn final WAL line, on the shared
  `wal_recovery::replay_wal_tolerating_torn_tail` seam, ALL four black-box
  verified by the catalogue: lumen `87d9363` (D04), ray `188c6c2` (D05),
  pulse seam `7c4a5e2` (D06), cinder `1886d94` (D07, via the CLI:
  list-items recovered the Hot placement after cinder.wal was torn). Each
  was fail-closed before its rewire; now the recovery branch. issue 006
  closed.
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

## The expectation

The observable contract: a store reopened after an abrupt death (a torn
final WAL line, the normal residue of a mid-write crash) must still serve
the intact, acknowledged records that preceded the torn line — it must
not become unreadable. D04 (lumen) and D05 (ray) pin this. How a store
meets it is the implementer's call; this issue states only the
observed-vs-expected behaviour.

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

## Cinder — the retraction was itself an over-correction (audit trail)

Three positions, in order, the last one correct:

1. System-level report: "cinder doc claims torn-tail tolerance while the
   code bricks." (Cited the wrong test as proof — a complete-but-
   malformed line WITH a trailing newline, which is correctly
   fail-closed, NOT a torn tail.)
2. My retraction (from `reports/cinder.md`): "cinder is NOT a torn-tail
   brick, doc accurate, never bricked." **This over-corrected.**
3. Implementer (msg 015, with timestamps): `reports/cinder.md` was
   written 2026-06-03 ~14:24, AFTER her cinder fix `1886d94` (~06:27).
   The per-module read therefore saw the POST-FIX state (open delegating
   to wal_recovery, doc accurate). BEFORE `1886d94`, cinder's open was a
   parse-or-die loop that DID brick on a real torn tail and the doc DID
   falsely claim "detected and ignored"; her commit rewired it onto the
   shared seam AND corrected the doc. So cinder genuinely bricked, was
   fixed, and the doc is accurate BECAUSE it was corrected.

D07 grounds the present state black-box: at `88d5a3f`, after tearing
cinder.wal, `list-items` recovers the Hot placement (exit 0,
items_after=1). cinder is verified, not credited. (The earlier "do not
fix the cinder doc" message to Bea Implementer was wrong and is
corrected in message 016.)

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
