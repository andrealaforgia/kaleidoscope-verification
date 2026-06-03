# 009 — `kaleidoscope-cli ingest` is non-atomic: partial commit + re-run double-ingest

- Status: `open` (black-box verified by K13)
- Severity: medium (data integrity; operational footgun, undocumented)
- Surface: kaleidoscope-cli `ingest` (operator binary).
- Opened: 2026-06-03
- Source: four-quadrants per-module report
  (`~/dev/kaleidoscope-4-quadrants-theory/reports/kaleidoscope-cli.md`,
  Q2 MEDIUM), black-box reproduced by **K13**.

## Observed (K13, HEAD 2e2ed58)

`ingest` flushes to Lumen + Cinder incrementally at `DEFAULT_BATCH_SIZE`
(100, `crates/kaleidoscope-cli/src/lib.rs:70`, no `--batch-size` flag).
A malformed NDJSON line AFTER an already-flushed batch aborts with a
typed `Error::ParseRecord` and a non-zero exit, but leaves the earlier
batches DURABLY COMMITTED.

K13 fed 100 valid records + 1 malformed line (101):

```
ingest1_exit=1        # aborts on line 101
count_after_1=100     # the first batch (100) is committed despite the abort
ingest2_exit=1        # same input, same abort
count_after_2=200     # re-run DOUBLE-INGESTS the committed prefix
```

So ingest is abort-on-first-bad-line but NOT all-or-nothing, and Lumen
append has no dedup at this layer, so an operator who re-runs the file
(corrected or not) double-ingests every already-committed batch.

## Why it matters

Silent partial persistence with a non-zero exit is a real footgun: the
non-zero exit reads as "nothing happened", but 100 records (and their
Cinder Hot placements) are durable. The natural operator response —
re-run — duplicates them. Neither the partial-commit nor the
double-ingest is tested or documented in kaleidoscope-cli.

The SAFE half is genuine and K13 also pins it: the malformed line
produces a TYPED error naming the line, a non-zero exit, and no
corruption — it does not silently swallow or panic. The defect is
purely the non-atomicity + lack of dedup.

## The expectation

K13 pins the observable contract: after a mid-stream abort, a re-run of
the same input must NOT increase the committed record count (an ingest
that aborts should leave the store as it found it, or be idempotent on
re-run). Today `count_after_1=100` and `count_after_2=200`, so K13
records the gap. How to close it is the implementer's call; this issue
only states the observed-vs-expected behaviour.

## Catalogue status

K13 is GREEN documenting the current behaviour as a regression guard. If
ingest becomes atomic (or idempotent), K13's `count_after_1`/`_after_2`
assertions change and it goes red — the prompt to update it and close
this issue.
