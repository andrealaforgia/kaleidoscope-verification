# X09 — xtask-regenerate-codex-corpus-idempotent

## Surface

Operations / build / supply chain. Build-engineer-facing.

## Behaviour

Running `cargo run --package regenerate-codex-corpus --bin
regenerate-codex-corpus` on a clean snapshot of kaleidoscope HEAD
produces zero diff against
`crates/codex/src/generated/semconv_0_27.rs` as committed. The
corpus is idempotent: regeneration on the committed source
returns the committed output.

## Source

- Catalogue-internal addition (post-Codex graduation, 2026-05-11):
  the xtask ritual landed at commit `8291bbd` per ADR-0023, and
  the catalogue tracks its idempotency as a build-engineer
  contract.
- External contract anchor:
  [`docs/product/architecture/adr-0023-codex-corpus-regeneration-ritual.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0023-codex-corpus-regeneration-ritual.md)
  "load-bearing rationale: nothing changes silently in CI, every
  corpus delta is a code review event".

## Verification

- Status: `satisfied`
- Last verified: 2026-05-11 UTC at HEAD.
- Method: `docker run rust:1.88-slim-bookworm` against the HEAD
  snapshot, runs `cargo run --release --package
  regenerate-codex-corpus`, then `diff -u` between the as-committed
  `semconv_0_27.rs` and the file after regeneration. Zero-diff is
  the contract.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA, dirty, host.
- [`evidence/xtask.stdout.txt`](evidence/xtask.stdout.txt) — xtask invocation log.
- [`evidence/semconv_0_27.committed.rs`](evidence/semconv_0_27.committed.rs) — corpus as committed at HEAD.
- [`evidence/semconv_0_27.regenerated.rs`](evidence/semconv_0_27.regenerated.rs) — corpus after running the xtask.
- [`evidence/semconv_0_27.diff`](evidence/semconv_0_27.diff) — `diff -u` between the two; expected to be empty.

## Issues

None.

## Notes

The xtask ships under `xtask/regenerate_codex_corpus/`, separate
from `crates/codex/` so the upstream `opentelemetry-semantic-conventions`
dep stays out of the runtime crate (per ADR-0023's "the dependency
lives HERE, not in crates/codex/Cargo.toml"). The catalogue
treats it as build tooling and verifies the idempotency property
the ritual hangs on.
