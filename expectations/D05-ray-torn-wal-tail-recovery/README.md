# D05 — ray-torn-wal-tail-recovery

## Surface

kaleidoscope-gateway (Ray sink) + trace-query-api, under a torn Ray WAL.
Operator-facing durability robustness. Durability set (#17 / N18), Ray
pillar. The Ray sibling of D04 (lumen).

## Behaviour

Given spans are ingested through the gateway into the Ray WAL, the
gateway is stopped cleanly, and the Ray WAL's trailing line is then
TORN (an incomplete JSON record with no newline — the residue of a
mid-write crash)
When trace-query-api opens that store
Then it recovers the intact prefix and ignores the torn tail: the
service starts (`running=true`, exit 0), and the window arm
`?service=d05-pilot` returns the intact spans, none corrupt.

The runner accepts either SAFE shape (graceful recovery OR clean
fail-closed with a clear error) and fails only on corrupt-data-served
or a silent crash; at `188c6c2` the recovery branch fires.

## Source

- wal-torn-tail-recovery-v0 rewired ray's open onto the shared
  `wal_recovery::replay_wal_tolerating_torn_tail` seam (pillar="ray"),
  feat `188c6c2` (after lumen at `87d9363`, seam crate at `0eb6227`).
- Anchor: `crates/ray/src/file_backed.rs` open delegates to the shared
  seam; WAL path is `<pillar_root>/ray.wal`.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-03 UTC at HEAD (`188c6c2`). GREEN, recovery
  branch: `tqapi_running=true`, `exit 0`, `query_code=200`,
  `query_count=10` (5 traces × root+child), all carrying
  `service=d05-pilot`, torn tail ignored.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14331` ingests `telemetrygen traces --service d05-pilot`,
  SIGTERM; the host-side `ray.wal` gets an incomplete JSON line appended
  (no newline); trace-query-api on the SAME `/data` (host port `19104`)
  is started and its window arm queried.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA
  `188c6c2`. dirty `yes`, but the dirty set is cinder's in-flight rewire
  (`crates/cinder/src/file_backed.rs`), NOT ray (committed clean); the
  build used `git archive HEAD`, so the recovery came from committed ray.
- [`evidence/ray.wal.before`](evidence/ray.wal.before),
  [`evidence/ray.wal.after`](evidence/ray.wal.after) — the WAL before
  and after the tear.
- [`evidence/d05-query.json`](evidence/d05-query.json) — the recovered
  spans.
- [`evidence/trace-query-api.stderr.txt`](evidence/trace-query-api.stderr.txt).

## Issues

Part of the evidence resolving
[issue 006](../../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md)
(`partial`): lumen (D04) and ray (D05) recover; cinder + pulse rewires
were still pending at this SHA.

## Notes

Same shared seam as D04, proven independently on the Ray store (distinct
WAL, span records) via the running trace-query-api, not by code-credit.
Unique high host ports (`14331`, `19104`) per N27.
