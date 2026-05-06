# X07 — license-manifests-correct

## Surface

Operations / supply chain. Build-engineer-facing.

## Behaviour

`crates/otlp-conformance-harness/Cargo.toml` and
`crates/spark/Cargo.toml` declare `license = "Apache-2.0"`;
`crates/aperture/Cargo.toml` declares `license = "AGPL-3.0-or-later"`.

This split is the contract from `LICENSING.md` and the project
README: SDK / protocol libraries are Apache-2.0; platform
components are AGPL-3.0-or-later.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X7**.
- External contract anchor:
  [`LICENSING.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/LICENSING.md)
  and [`README.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/README.md)
  ("Platform components — AGPL-3.0-or-later"; "SDKs and protocol
  libraries — Apache-2.0").

## Verification

- Status: `satisfied`
- Last verified: 2026-05-07T00:34Z
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: static read of each crate's `Cargo.toml` from
  `git archive HEAD` (no working-tree contamination); the literal
  `license = ...` line is captured verbatim per file.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/citations.txt`](evidence/citations.txt) — verbatim:
  ```
  === crates/otlp-conformance-harness/Cargo.toml ===
  9:license = "Apache-2.0"

  === crates/spark/Cargo.toml ===
  10:license = "Apache-2.0"

  === crates/aperture/Cargo.toml ===
  10:license = "AGPL-3.0-or-later"
  ```

## Issues

None.

## Notes

`crates/sieve/Cargo.toml` (Slice 01 just landed) carries
`license = "AGPL-3.0-or-later"` per its header comment ("Symmetric
with Aperture"). Sieve was not in the source feed's X7 list because
Sieve is newer than the feed; its license is consistent with the
contract and is a follow-on observation, not a violation.
