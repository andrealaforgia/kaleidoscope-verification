# K13 — cli-ingest-non-atomic-partial-commit

## Surface

kaleidoscope-cli `ingest` (operator binary). Data-integrity behaviour.
Grounds [issue 009](../../issues/009-cli-ingest-non-atomic-partial-commit-double-ingest.md).

## Behaviour (contract under test)

Given an NDJSON stream of 100 valid `LogRecord` lines followed by a
malformed line 101
When `kaleidoscope-cli ingest acme /data` consumes it
Then ingest is ALL-OR-NOTHING: it aborts with a non-zero exit and commits
NOTHING (a file with any malformed line ingests zero records), and
re-running the same bad input still commits nothing — no partial commit,
no double-ingest.

## Status: `broken` — RED at HEAD, grounding issue 009

At `8f388a5` ingest is NON-ATOMIC. It flushes batches incrementally
(`DEFAULT_BATCH_SIZE = 100`), so 100 valid records followed by a malformed
line 101 leaves the first batch of 100 durably COMMITTED while ingest
aborts non-zero, and re-running the same input DOUBLE-INGESTS the prefix
(`count_after_1=100`, `count_after_2=200`; Lumen append has no dedup). The
SAFE half holds either way (typed abort, non-zero exit, no corruption),
but the partial-commit + double-ingest is the data-integrity footgun.

The runner therefore exits non-zero here by design and records the failing
contract. Transition-proof (the A17/B03 pattern): it asserts the
all-or-nothing contract and flips GREEN automatically when
`cli-ingest-atomic-v0` (ADR-0064, buffer-all-then-flush; DISCUSS `f03b22e`,
DESIGN `8f388a5` at the time of writing — not yet DELIVERED) lands, with
no rewrite.

## Verification

- Status: `broken` (RED, known defect; tracks issue 009)
- Last verified: 2026-06-05 UTC at HEAD (`8f388a5`). RED:
  `ingest1_exit=1`, `count_after_1=100` (partial commit), `ingest2_exit=1`,
  `count_after_2=200` (double-ingest).
- Method: `harness/run-kaleidoscope-cli.sh`. 100 valid NDJSON records
  (body `k13-rec-NNN`) + one malformed line are piped to `ingest` twice on
  the same `/data`; `read` counts after each. The runner classifies
  atomic (0/0 → GREEN) vs non-atomic (100/200 → RED) with the
  both-exits-non-zero safe invariant held either way.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `8f388a5`.
- [`evidence/K13.stdout.txt`](evidence/K13.stdout.txt) — exit codes + counts.
- [`evidence/ingest1.out`](evidence/ingest1.out) — the typed abort.
- [`evidence/read-after-2.ndjson`](evidence/read-after-2.ndjson) — the
  200 records after the re-run (the double-ingest).

## Source

- four-quadrants per-module report (kaleidoscope-cli, Q2 MEDIUM:
  partial-batch commit / re-run double-ingest), filed as issue 009.
- `crates/kaleidoscope-cli/src/lib.rs:70` (`DEFAULT_BATCH_SIZE = 100`),
  incremental flush + typed abort. Fix in flight: `cli-ingest-atomic-v0`
  (ADR-0064, buffer-all-then-flush, all-or-nothing on a parse error).

## Notes

Was `satisfied` (pinning the observed footgun), which would have BROKEN on
the fix (a satisfied expectation failing because the bug was fixed).
Retrofitted to the transition-proof RED-grounding pattern on 2026-06-05 so
it flips GREEN on the DELIVER instead. The first K-prefix `broken`.
