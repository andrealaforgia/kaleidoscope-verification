# K13 — cli-ingest-non-atomic-partial-commit

## Surface

kaleidoscope-cli `ingest` (operator binary). Data-integrity behaviour.

## Behaviour

Given an NDJSON stream of 100 valid `LogRecord` lines followed by a
malformed line 101
When `kaleidoscope-cli ingest acme /data` consumes it
Then it aborts with a non-zero exit (typed parse error, no corruption),
BUT the first batch of 100 — already flushed at `DEFAULT_BATCH_SIZE` —
is left durably committed; and re-running the SAME input commits another
100, so a subsequent `read` returns 200. Ingest is abort-on-bad-line but
NOT all-or-nothing, and there is no dedup.

## Source

- four-quadrants per-module report (kaleidoscope-cli, Q2 MEDIUM:
  partial-batch commit / re-run double-ingest), filed as
  [issue 009](../../issues/009-cli-ingest-non-atomic-partial-commit-double-ingest.md).
- `crates/kaleidoscope-cli/src/lib.rs:70` (`DEFAULT_BATCH_SIZE = 100`),
  `:215-226` (incremental flush), `:210-213` (typed abort).

## Verification

- Status: `satisfied` (documents the observed footgun + the safe half)
- Last verified: 2026-06-03 UTC at HEAD (`2e2ed58`). GREEN:
  `ingest1_exit=1`, `count_after_1=100` (partial commit), `ingest2_exit=1`,
  `count_after_2=200` (double-ingest).
- Method: `harness/run-kaleidoscope-cli.sh`. 100 valid NDJSON records
  (body `k13-rec-NNN`) + one malformed line are piped to `ingest` twice
  on the same `/data`; `read` counts the `k13-rec-` records after each.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `2e2ed58`.
- [`evidence/K13.stdout.txt`](evidence/K13.stdout.txt) — exit codes + counts.
- [`evidence/ingest1.out`](evidence/ingest1.out) — the typed abort.
- [`evidence/read-after-2.ndjson`](evidence/read-after-2.ndjson) — the
  200 records after the re-run (the double-ingest).

## Issues

[issue 009](../../issues/009-cli-ingest-non-atomic-partial-commit-double-ingest.md)
— the non-atomic-ingest + double-ingest footgun this expectation pins.

## Notes

GREEN means the footgun is present as observed. K13 also asserts the
SAFE half (typed abort, non-zero exit, no corruption) — genuine
restraint. If ingest becomes atomic or idempotent, the count assertions
flip and K13 goes red, prompting the update + issue 009 close.
