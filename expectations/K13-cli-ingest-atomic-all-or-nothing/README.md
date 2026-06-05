# K13 — cli-ingest-atomic-all-or-nothing

## Surface

kaleidoscope-cli `ingest` (operator binary). Data-integrity behaviour.
Resolves [issue 009](../../issues/009-cli-ingest-non-atomic-partial-commit-double-ingest.md).

## Behaviour

Given an NDJSON stream of 100 valid `LogRecord` lines followed by a
malformed line 101
When `kaleidoscope-cli ingest acme /data` consumes it
Then ingest is ALL-OR-NOTHING: it aborts with a non-zero exit naming the
bad line and commits NOTHING (the store record count is unchanged at 0,
not 100), and re-running the same bad input still commits nothing. A file
with any malformed line ingests zero records, however many times it is
run. No partial commit, no double-ingest of a partial prefix.

## History — this expectation flipped

Authored to ground issue 009 (the four-quadrants kaleidoscope-cli
footgun): at the original SHA ingest flushed batches incrementally
(`DEFAULT_BATCH_SIZE = 100`), so 100 valid records + a malformed line 101
left the first batch durably committed (`count_after_1=100`) and a re-run
double-ingested it (`count_after_2=200`). The implementer fixed it
(`cli-ingest-atomic-v0`, ADR-0064, feat `fdfbc28`): ingest now parses the
WHOLE input into memory before committing any batch; the first unparseable
line returns an error with nothing opened-to and nothing flushed.

K13 was written transition-proof (the A17/B03 pattern): it asserts the
all-or-nothing contract and classifies atomic (0/0 → GREEN) vs non-atomic
(100/200 → RED), so it flipped GREEN on the DELIVER with no rewrite. It
held correctly RED through DISCUSS/DESIGN/DEVOPS/DISTILL (the feat was
committed only at `fdfbc28`).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`fdfbc28`). GREEN:
  `ingest1_exit=1`, `count_after_1=0`, `ingest2_exit=1`, `count_after_2=0`
  — the malformed input committed nothing, twice.
- Method: `harness/run-kaleidoscope-cli.sh`. 100 valid NDJSON records
  (body `k13-rec-NNN`) + one malformed line are piped to `ingest` twice on
  the same `/data`; `read` counts after each. The runner asserts the
  all-or-nothing 0/0, with both-exits-non-zero as the safe invariant.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `fdfbc28`.
- [`evidence/K13.stdout.txt`](evidence/K13.stdout.txt) — exit codes + counts (0/0).
- [`evidence/ingest1.out`](evidence/ingest1.out) — the typed abort naming the line.
- [`evidence/read-after-2.ndjson`](evidence/read-after-2.ndjson) — empty after both runs.

## Source

- `crates/kaleidoscope-cli/src/lib.rs` — ingest buffers the whole input and
  validates before committing any batch (ADR-0064 buffer-all-then-flush);
  the first unparseable line returns `Err(ParseRecord{line})` with nothing
  committed. feat `fdfbc28`.

## Notes

SCOPE (implementer message 023): K13 covers only the MALFORMED-input case
(the issue-009 fix). A re-run of a SUCCESSFUL, fully-valid ingest STILL
doubles, because lumen has no idempotency key — that is a separate,
larger concern deferred to a future `ingest-dedup-v0`, tracked
`009-adjacent` in [known-gaps.md](../../known-gaps.md), NOT part of K13 and
NOT issue 009. Was `broken` (RED grounding 009) and retrofitted
transition-proof on 2026-06-05; flipped `satisfied` on the DELIVER.
