# D03 — ray-acked-span-survives-gateway-kill9

## Surface

kaleidoscope-gateway (OTLP receiver, Ray sink) + trace-query-api, under
a hard process kill. Operator-facing durability. Durability set
(`known-gaps.md` #17), Ray pillar.

## Behaviour

Given the gateway has ingested and ACKED spans into the Ray store
When the gateway process is hard-killed with SIGKILL (`kill -9`)
Then the acked spans are not lost: reopening the same Ray store (through
trace-query-api) replays the WAL and the spans are queryable via the
window arm (`?service=d03-pilot`), all carrying that service.

## Source

- Durability thesis for the Ray pillar (ADR-0049 family; WAL recovery).
- Mechanism anchor:
  [`crates/ray/src/file_backed.rs:393`](https://github.com/andrealaforgia/kaleidoscope/blob/eef7576ea427e568739adc38a63257b4dafde8e0/crates/ray/src/file_backed.rs#L393)
  — `append_wal` does `write_all` + `flush()` (hands bytes to the kernel
  via `write(2)`) BEFORE `ingest` returns the receipt the gateway acks
  on; `FileBackedTraceStore::open` replays the WAL.

## Scope honesty

Ray's contract matches Lumen's (D01), NOT Pulse's (D02): `append_wal`
`flush()`es to the kernel but does NOT `fsync`. So this is PROCESS-kill
durability (the OS page cache survives the dead process), NOT
OS-crash / power-loss durability. The claim asserted is precisely
"acked survives kill -9". (If Ray were ever expected to be power-loss
durable, that would need an `fsync` on the WAL append path like Pulse's,
and its absence would be a finding — but ADR-0049's per-pillar fsync
discipline currently pins it on Pulse, not Ray, so no issue is raised.)

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`eef7576`, clean tree). GREEN:
  `telemetrygen_exit=0`, `gateway_kill_exit=137` (SIGKILL),
  `query_code=200`, `survivors=10` — all ten acked spans recovered,
  every one carrying `service.name=d03-pilot`.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14326` (run WITHOUT `--rm` for exit-code inspection);
  `telemetrygen traces --traces 5 --service d03-pilot`;
  `docker kill --signal=KILL` the gateway; then trace-query-api on the
  SAME `/data` (host port `19101`) queried on the window arm.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA
  `eef7576`, dirty `no`.
- [`evidence/D03.stdout.txt`](evidence/D03.stdout.txt) — ack, the `137`
  kill exit, the post-kill query code and survivor count.
- [`evidence/d03-after-kill.json`](evidence/d03-after-kill.json) — the
  spans recovered AFTER the SIGKILL.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/trace-query-api.stderr.txt`](evidence/trace-query-api.stderr.txt),
  [`evidence/telemetrygen.stderr.txt`](evidence/telemetrygen.stderr.txt).

## Issues

None.

## Notes

Third and last of the durability set for the pillars with a direct
gateway → read-API path (D01 Lumen, D02 Pulse, D03 Ray). The other v1
pillars (Cinder, Strata, Sluice, Beacon RuleState) have no
gateway-ingest → read-API round-trip, so this exact kill-9 shape does
not apply to them; that boundary is recorded in `known-gaps.md` #17.
Unique high host ports (`14326`, `19101`) per N27.
