# D02 — pulse-acked-metric-survives-gateway-kill9

## Surface

kaleidoscope-gateway (OTLP receiver, Pulse sink) + query-api, under a
hard process kill. Operator-facing durability. Durability set
(`known-gaps.md` #17), Pulse pillar.

## Behaviour

Given the gateway has ingested and ACKED a metric into the Pulse store
When the gateway process is hard-killed with SIGKILL (`kill -9`), so no
graceful shutdown runs
Then the acked metric is not lost: reopening the same Pulse store
(through query-api) replays the WAL and the series is queryable
(`status=success`, `__name__=gen`).

## Source

- Durability thesis for the Pulse pillar (ADR-0049 fsync-honesty).
- Mechanism anchor:
  [`crates/pulse/src/file_backed.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/5c2ebb0ff9639b5cf61a5e604f8e0a36c0d138c3/crates/pulse/src/file_backed.rs)
  — `append_wal` does `wal.flush()` THEN
  `fsync_backend.fsync_file()` (`sync_all`, ADR-0049 §4) per record
  BEFORE `ingest` returns the `IngestReceipt` the gateway acks on;
  `FileBackedMetricStore::open` replays the WAL.

## Scope honesty

Pulse's guarantee is actually STRONGER than Lumen's (D01): it
fsyncs (`sync_all`) before the ack, not merely `flush()`es to the
kernel. So an acked Pulse metric is durable on stable storage and would
survive an OS crash / power loss too, not just a process kill. This
expectation, however, only DEMONSTRATES process-kill survival — the
dockerised harness cannot power-cycle the disk. The claim asserted here
is therefore "acked survives kill -9"; the stronger power-loss property
is true by the fsync-before-ack mechanism but is not black-box exercised.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`5c2ebb0`, clean tree). GREEN:
  `telemetrygen_exit=0` (gateway acked, therefore fsync'd),
  `gateway_kill_exit=137` (128 + SIGKILL), `query_code=200`,
  `status=success`, recovered series `__name__=gen` /
  `service.name=d02-pilot`.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14325` (run WITHOUT `--rm` so the post-kill exit code is
  inspectable); `telemetrygen metrics --otlp-attributes
  service.name=d02-pilot`; `docker kill --signal=KILL` the gateway; then
  query-api on the SAME `/data` (host port `19100`) queried with
  `query=gen`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA
  `5c2ebb0`, dirty `no`.
- [`evidence/D02.stdout.txt`](evidence/D02.stdout.txt) — ack, the `137`
  kill exit, the post-kill query code.
- [`evidence/d02-after-kill.json`](evidence/d02-after-kill.json) — the
  series recovered AFTER the SIGKILL.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/query-api.stderr.txt`](evidence/query-api.stderr.txt),
  [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt).

## Issues

None.

## Notes

Second of the durability set (after D01 / Lumen). D03 (Ray / spans via
trace-query-api) is the natural next. Unique high host ports (`14325`,
`19100`) per N27.
