# K11 — kaleidoscope-cli-unknown-flag-rejected

## Surface

`kaleidoscope-cli` operator binary. Operator-facing.

## Behaviour

`kaleidoscope-cli ingest …` (and `read`, `stats`) reject an
unknown flag (e.g. a typo like `--observe-otlpp`) with a non-zero
exit and a diagnostic on stderr — instead of silently accepting
the flag and proceeding as if it were absent.

## Source

- Contract anchor: commit `307e447` ("feat(kaleidoscope-cli): reject
  unknown subcommand flags, re-anchoring K11"), the clean nWave rebuild
  of the contract. The original anchor `e7fbee0` was reverted en bloc
  by `e3a8cad` (N14); this commit is NOT in the reverted set, so the
  anchor check passes ("anchor 307e447 still applies ... no revert
  commits"). `crates/kaleidoscope-cli/src/main.rs` now runs a shared
  `reject_unknown_flags` helper per subcommand during parse.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-01 UTC at HEAD (`2bab0b6`, clean tree; the K11
  feat `307e447` is in this build). GREEN at first attempt (after a
  catalogue-side `ec()` helper typo fixed). Re-anchored from held → the
  unknown-flag rejection contract is real in HEAD again, through a
  proper nWave flow.
- Observable contract (four cases, all asserted):
  - `kaleidoscope-cli --bogus` → exit 2 + usage block on stderr;
  - `kaleidoscope-cli bogus-subcommand` → exit 2 + usage;
  - `kaleidoscope-cli read acme /data --bogus` → exit 2 + usage —
    **the re-anchored fix**: this used to exit 0 and silently ignore
    the unknown flag (a known subcommand with an unknown flag);
  - `kaleidoscope-cli read acme /data --since <ts>` → a KNOWN flag is
    parsed, NOT rejected (exit 0 on the empty store, no usage block).
- Method: `harness/run-kaleidoscope-cli.sh` builds the CLI image from
  the snapshot's project Dockerfile; four `docker run` invocations
  capture exit code + stderr per case. The anchor check (`anchor.yaml`,
  commit `307e447`) confirms the anchoring commit is reachable and not
  reverted before `satisfied` is granted.

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
