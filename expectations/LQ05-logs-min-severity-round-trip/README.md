# LQ05 — logs-min-severity-round-trip

## Surface

kaleidoscope-gateway (OTLP receiver, Lumen sink) + log-query-api
(`/api/v1/logs` over Lumen). End-to-end, operator/integrator-facing.

## Behaviour

Given log records of mixed severity are ingested through the gateway
into the durable Lumen store and read back through log-query-api over
the same store and tenant
When the read is parameterised with `min_severity`
Then the floor actually filters across the boundary:

- with no `min_severity`, both an INFO batch (severity_number `9`) and
  an ERROR batch (severity_number `17`) are returned (control: both
  were ingested);
- `min_severity=WARN` (floor `13`) returns only records whose
  `severity_number >= 13`: the ERROR records are present, every INFO
  record is excluded;
- `min_severity=ERROR` (floor `17`) returns only records whose
  `severity_number >= 17`.

## Source

- kaleidoscope log-query-severity-filter-v0 (feat `e281fca`, ADR-0052),
  tracked as gap N23 until now.
- External contract anchor: `parse_min_severity` →
  `Predicate::new().min_severity(floor)` at
  [`crates/log-query-api/src/lib.rs`](https://github.com/andrealaforgia/kaleidoscope/blob/a898e757b88f2c81b311d320c4ec510b879b4928/crates/log-query-api/src/lib.rs);
  severity constants (INFO=9, WARN=13, ERROR=17) at
  [`crates/lumen/src/record.rs:33`](https://github.com/andrealaforgia/kaleidoscope/blob/a898e757b88f2c81b311d320c4ec510b879b4928/crates/lumen/src/record.rs#L33).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-31 UTC at HEAD (`a898e757`). GREEN at first
  attempt: full result severities `[9,17]` (12 records); `min_severity=WARN`
  severities `[17]` (6 records, all INFO excluded); `min_severity=ERROR`
  severities `[17]`.
- Method: dockerised harness via `harness/run-eg.sh`. Gateway on host
  port `14321`; two `telemetrygen:v0.114.0` log batches, one
  `--severity-number 9 --body lq05-info-marker` and one
  `--severity-number 17 --body lq05-error-marker`; SIGTERM to flush
  Lumen; then log-query-api on the SAME `/data` (host port `19094`)
  queried three ways. Assertions key on both the wire `severity_number`
  (a bare i32 from `SeverityNumber(pub i32)`) and the body marker, so a
  floor that leaked or over-filtered is caught either way.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — pinning
  record (SHA `a898e757`, dirty `yes`, but the dirty set is the dev
  side's in-flight perf-kpi-ci-gating-v0 DELIVER editing `tests/*.rs`
  and `ci.yml`; zero lib source under crates/{lumen,log-query-api,
  kaleidoscope-gateway}/src; the build used `git archive HEAD`; see
  `evidence/kaleidoscope-dirty.status`).
- [`evidence/lq05-full.json`](evidence/lq05-full.json),
  [`evidence/lq05-warn.json`](evidence/lq05-warn.json),
  [`evidence/lq05-error.json`](evidence/lq05-error.json) — the three
  responses; severity distributions are the proof.
- [`evidence/telemetrygen.info.stderr.txt`](evidence/telemetrygen.info.stderr.txt),
  [`evidence/telemetrygen.error.stderr.txt`](evidence/telemetrygen.error.stderr.txt),
  [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/log-query-api.stderr.txt`](evidence/log-query-api.stderr.txt).

## Issues

None.

## Notes

Closes gap N23 (log-query-severity-filter-v0 was real but unverified at
the running surface). Fifth expectation on the gateway→Lumen→log-query-api
fixture (LQ02 body_contains, LQ03 body_regex, LQ04 pagination, LQ05
min_severity). Unique high host ports (`14321`, `19094`) per N27.
