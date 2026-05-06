# X08 — forbid-unsafe-code-in-spark-and-aperture

## Surface

Operations / supply chain. Build-engineer-facing.

## Behaviour

`#![forbid(unsafe_code)]` is present at crate root in both
`crates/spark/src/lib.rs` and `crates/aperture/src/lib.rs`. The
attribute is greppable and rejects any unsafe block at compile
time, providing a lint-level guarantee that the crate's public
surface contains no unsafe Rust.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X8**.
- External anchor: the source files themselves at `HEAD`.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-07T00:34Z
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: static `git archive HEAD` followed by `grep -nE
  "forbid.*unsafe_code"` against each crate's `lib.rs`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/citations.txt`](evidence/citations.txt) — verbatim:
  ```
  === crates/spark/src/lib.rs ===
  59:#![forbid(unsafe_code)]

  === crates/aperture/src/lib.rs ===
  29:#![forbid(unsafe_code)]
  ```

## Issues

None.

## Notes

`crates/otlp-conformance-harness/src/lib.rs` and
`crates/sieve/src/lib.rs` may also carry the attribute (they are
out of scope for the source feed item); follow-on expectations can
extend the surface as the workspace grows.
