# K11 — kaleidoscope-cli-unknown-flag-rejected

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli ingest …` (and `read`, `stats`) reject an
unknown flag (e.g. a typo like `--observe-otlpp`) with a non-zero
exit and a diagnostic on stderr — instead of silently accepting
the flag and proceeding as if it were absent.

## Source

- Original contract anchor: commit `e7fbee0` ("ingest + compact
  reject unknown flags loudly"), part of the 31-commit overnight
  session that was reverted en bloc.

## Verification

- Status: `held`
- Reason: anchored to a reverted commit. The unknown-flag
  rejection landed in `e7fbee0` and was undone by `e3a8cad`
  ("revert: drop overnight session — methodology violation, not
  nWave-shaped"). The current `parse_observe_otlp` in
  `crates/kaleidoscope-cli/src/main.rs` is back to the silent-
  accept shape; an unknown flag passes through with exit 0.

## What we observed

A live snapshot run of K11 at HEAD shows `docker run …
ingest acme /data --observe-otlpp /tmp/wrong.log` exits **0**
with `ingest ok: records=0`. No stderr diagnostic. The runner is
correct; the contract is no longer in HEAD.

## Resume condition

Promote back to `pending`, then re-verify, when the unknown-flag
rejection contract is reintroduced through a proper nWave flow
(DISCUSS → DESIGN → DEVOPS → DISTILL → DELIVER) and a new
contract-anchoring commit lands. Update the "Source" anchor to
that new SHA at that point.

## Evidence

The `evidence/` directory carries the last-attempt traces from
2026-05-18 (HEAD `1df2d590` then `20777cb`, both post-revert)
that proved the contract is absent.

## Issues

None. The catalogue's job here was to detect the regression: the
expectation fails loudly, which is the correct signal.

## Notes

This is the second time the EDD catalogue has caught a
methodology-revert. Future K-prefix work should check, before
opening a contract, that the anchoring commit survives
`git log e3a8cad..HEAD -- <path>`.
