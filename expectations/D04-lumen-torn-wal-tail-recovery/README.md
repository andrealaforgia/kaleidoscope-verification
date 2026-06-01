# D04 — lumen-torn-wal-tail-recovery

## Surface

lumen `FileBackedLogStore` recovery, observed via log-query-api.
Operator-facing durability robustness. Durability set
(`known-gaps.md` #17 / N18).

## Behaviour

Given a Lumen store whose WAL ends in a TORN trailing line (an
incomplete JSON record with no newline — the exact residue of a
mid-write crash or power loss)
When log-query-api opens that store
Then it must NOT serve corrupt or partial data. The observed behaviour
satisfies that safe invariant: it FAILS CLOSED — exits non-zero and
never binds — with a clear, specific
`PersistenceFailed { reason: "WAL parse error at line N: ..." }`. It does
not crash silently and it does not surface the torn record as data.

This is the deterministic complement to D01-D03 (which kill AFTER the
ack). Rather than race a SIGKILL into the tiny `write_all`+`flush`
window, D04 corrupts the WAL tail on disk deterministically and observes
the reopen. The runner accepts either safe shape — graceful recovery of
the intact prefix (running, 200, no torn record) OR clean fail-closed
with a clear error — and fails only on corrupt-data-served or a silent
crash.

## Source

- Durability-robustness facet of N18 (torn-write recovery).
- Mechanism anchor:
  [`crates/lumen/src/file_backed.rs:104`](https://github.com/andrealaforgia/kaleidoscope/blob/eef7576ea427e568739adc38a63257b4dafde8e0/crates/lumen/src/file_backed.rs#L104)
  — `open` parses every WAL line through `serde_json::from_str` and
  returns `PersistenceFailed` on the first bad line.

## Verification

- Status: `satisfied` (asserts the SAFE invariant only)
- Last verified: 2026-06-01 UTC at HEAD (`eef7576`). Observed:
  6 well-formed records ingested + gateway stopped cleanly; one torn
  partial line appended to `lumen.wal`; log-query-api then
  `lqapi_running=false`, `lqapi_exitcode=1`, stderr
  `PersistenceFailed { reason: "WAL parse error at line 7: EOF while parsing an object at line 1 column 86" }`,
  no data served. Fail-closed branch satisfied.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14327` ingests `--body d04-survivor-marker`, stopped with
  SIGTERM; the host-side `lumen.wal` then gets an incomplete JSON line
  appended (no newline); log-query-api on the SAME `/data` (host port
  `19102`) is started and its open behaviour + any query observed.

## The brittle half (issue 006)

The fail-closed behaviour is SAFE but brittle: a single torn trailing
line — the *normal* residue of an abrupt death — blocks recovery of ALL
the intact, acked, durable records before it, with no automatic
truncation. That durability-robustness gap is filed as
[issue 006](../../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md)
and flagged to the implementer. D04 deliberately asserts only the safe
invariant (no corrupt data) so it stays GREEN whichever way issue 006 is
resolved; if torn-tail truncation lands, D04's already-coded recovery
branch (intact prefix served, torn tail ignored) becomes the asserted
path.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `eef7576`.
- [`evidence/D04.stdout.txt`](evidence/D04.stdout.txt) — the observed
  running/exit/query values.
- [`evidence/lumen.wal.before`](evidence/lumen.wal.before),
  [`evidence/lumen.wal.after`](evidence/lumen.wal.after) — the WAL before
  and after the tear.
- [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt)
  — the `PersistenceFailed` open error.

## Issues

[issue 006](../../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md)
(the brittle-recovery half).

## Notes

Fourth of the durability set; the deterministic torn-write complement to
D01-D03's post-ack kills. Unique high host ports (`14327`, `19102`) per
N27.
