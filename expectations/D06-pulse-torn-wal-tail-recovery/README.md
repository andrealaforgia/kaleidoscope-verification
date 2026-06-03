# D06 — pulse-torn-wal-tail-recovery

## Surface

kaleidoscope-gateway (Pulse sink) + query-api, under a torn Pulse WAL.
Operator-facing durability robustness. Durability set (#17 / N18), Pulse
pillar. The Pulse member of the issue-006 close (after D04 lumen, D05 ray).

## Behaviour

Given a metric is ingested through the gateway into the Pulse WAL, the
gateway is stopped cleanly, and the Pulse WAL's trailing line is then
TORN (incomplete JSON, no newline)
When query-api opens that store
Then it recovers the intact prefix and ignores the torn tail: the
service starts (`running=true`, exit 0) and `query_range?query=gen`
returns `status=success` with the recovered series (`__name__=gen`).

The runner accepts either SAFE shape (recovery OR clean fail-closed) and
fails only on corrupt-data-served or a silent crash; at `1653a0d` the
recovery branch fires.

## Source

- wal-torn-tail-recovery-v0 rewired pulse's open onto the shared
  `wal_recovery::replay_wal_tolerating_torn_tail` seam (pillar="pulse"),
  feat `7c4a5e2`.
- Anchor: `crates/pulse/src/file_backed.rs:168`; WAL path
  `<pillar_root>/pulse.wal`.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-04 UTC at HEAD (`1653a0d`). GREEN, recovery
  branch: `qapi_running=true`, exit 0, `query_code=200`,
  `result_status=success`, `result_count=1`, `__name__=gen`.
- Method: `harness/run-eg.sh`. Gateway on host port `14332` ingests one
  `telemetrygen` metric, SIGTERM; the host-side `pulse.wal` gets an
  incomplete JSON line appended (no newline); query-api on the SAME
  `/data` (host port `19105`) is queried.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `1653a0d`.
- [`evidence/pulse.wal.before`](evidence/pulse.wal.before),
  [`evidence/pulse.wal.after`](evidence/pulse.wal.after) — WAL before/after
  the tear.
- [`evidence/d06-query.json`](evidence/d06-query.json) — the recovered
  series.

## Issues

Part of the evidence that closed
[issue 006](../../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md):
lumen (D04), ray (D05), pulse (D06) black-box; cinder credited to the
implementer's acceptance tests (it is reached via the CLI, not a
gateway→read-API path).

## Notes

Pulse is the only store that fsyncs (so a real torn residue is rarer),
but the shared recovery seam handles a torn final line regardless, and
D06 proves it on the running query-api. Unique high host ports (`14332`,
`19105`) per N27.
