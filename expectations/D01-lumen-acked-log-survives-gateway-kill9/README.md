# D01 — lumen-acked-log-survives-gateway-kill9

## Surface

kaleidoscope-gateway (OTLP receiver, Lumen sink) + log-query-api, under
a hard process kill. Operator-facing durability. First expectation of
the durability set (`known-gaps.md` #17).

## Behaviour

Given the gateway has ingested and ACKED a log record into the Lumen
store
When the gateway process is hard-killed with SIGKILL (`kill -9`), so no
graceful shutdown and no Drop-flush ever runs
Then the acked record is not lost: reopening the same Lumen store
(through log-query-api) replays the WAL and the record is queryable.

This is distinct from LQ02, which used SIGTERM (the graceful Drop-flush
path). D01 exercises the WAL-flush-BEFORE-ack contract: an ack the
gateway returns implies the record was already handed to the kernel, so
a process kill cannot lose it.

## Source

- Durability thesis for the Lumen pillar (ADR-0049 fsync-honesty family;
  WAL recovery on open).
- Mechanism anchor:
  [`crates/lumen/src/file_backed.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/00433863cac54e9522d40da5eba810e7886e710a/crates/lumen/src/file_backed.rs)
  — `append_wal` does `wal.write_all(...)` then `wal.flush()` (hands the
  bytes to the kernel via `write(2)`) BEFORE `ingest` returns the
  `IngestReceipt` the gateway acks on; `FileBackedLogStore::open`
  replays the WAL if `wal_path` exists.

## Scope honesty

This proves durability against a **process kill** (SIGKILL), where the
OS page cache survives the dead process. It does NOT prove durability
against an **OS crash / power loss** — that needs `fsync`/`sync_data`,
which `append_wal` does not call (it `flush()`es to the kernel, not to
the platter). A power-loss durability expectation would need a stronger
mechanism (and probably fault injection at the block layer) and is out
of scope here. The claim is precisely "acked survives kill -9", no more.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`0043386`, clean tree). GREEN:
  `telemetrygen_exit=0` (the gateway acked), `gateway_kill_exit=137`
  (128 + SIGKILL, proving a hard kill, not a graceful stop),
  `query_code=200`, `survivors=6` — all six acked records carrying the
  needle were recovered from the WAL on reopen.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14324` (run WITHOUT `--rm` so its post-kill exit code can be
  inspected); `telemetrygen logs --body d01-survivor-marker`;
  `docker kill --signal=KILL` the gateway; then log-query-api on the
  SAME `/data` (host port `19099`) queried with
  `body_contains=d01-survivor-marker`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA
  `0043386`, dirty `no`.
- [`evidence/D01.stdout.txt`](evidence/D01.stdout.txt) — telemetrygen
  ack, the `137` kill exit code, the post-kill query code and survivor
  count.
- [`evidence/d01-after-kill.json`](evidence/d01-after-kill.json) — the
  records recovered AFTER the SIGKILL.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt),
  [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt).

## Issues

None.

## Notes

Opens the durability set (#17), Lumen pillar. The same kill-9 shape
applies to the other v1 pillars (Pulse via query-api, Ray via
trace-query-api) and is the natural next batch (D02, D03). Unique high
host ports (`14324`, `19099`) per N27.
