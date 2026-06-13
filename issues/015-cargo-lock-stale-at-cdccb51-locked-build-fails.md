# 015 — committed Cargo.lock is stale at cdccb51: every `--locked` build fails

- Status: `resolved` (2026-06-13) at kaleidoscope HEAD `2552981`
  (`read-path-query-api-auth-v0` slice 2) — X01 GREEN, exit 0, 215
  `test result: ok`, no lock error. Slice 2 added the `jsonwebtoken` /
  `reqwest` / `serde` dev-deps to the `log-query-api` (+10) and
  `trace-query-api` (+11) manifests, reconciling them with the lock edges
  that were already present (and over-specified) at `cdccb51`. The committed
  `Cargo.lock` is byte-identical across the two SHAs; the fix landed in the
  manifests, not the lock. Correction to the framing below: the lock was not
  "missing edges" for the new deps — it already carried them and was AHEAD
  of the slice-1 manifests, which is why `--locked` demanded regeneration.
  Was: `open` (2026-06-08). Grounded RED by **X01** at kaleidoscope HEAD
  `cdccb51` (`read-path-query-api-auth-v0` slice 1).
- Severity: high (the committed tree does not build under `--locked` — CI, all
  three query-API Docker images, and the pre-commit hook all fail; no `--locked`
  consumer can build the tree, and it blocks black-box verification of the
  read-path-auth feature itself).
- Surface: `Cargo.lock` (workspace) vs `crates/query-api/Cargo.toml` +
  `crates/query-http-common/Cargo.toml`.
- Opened: 2026-06-08
- Source: found by the verifier attacking read-path-query-api-auth-v0 — the
  query-api Docker build failed while running the backward-compat checks
  (Q01/Q08), and the cause was isolated to the lock, not the feature code.

## The gap

`cdccb51` added direct dependencies (`jsonwebtoken = "9"`, `reqwest`,
`serde` derive, `tracing`) to the `query-api` and `query-http-common`
manifests (Cargo.toml +13 / +16 lines) but committed a `Cargo.lock` change of
only +7 lines that does not record the new dependency edges in those packages'
lock entries. The committed tree is therefore inconsistent under `--locked`:

```
$ cargo test --workspace --all-targets --locked
error: the lock file /src/Cargo.lock needs to be updated but --locked was passed to prevent this
```

`cargo update --workspace --locked` reports "Locking 0 packages to latest
compatible versions" (the package versions are fine) and still fails — so this
is a missing dependency-edge record, not a version drift.

## Not a harness artefact

Reproduced from a fresh `git archive cdccb51` with a CLEAN cargo registry over
the network (`Updating crates.io index` succeeds, then the same `--locked`
failure). It is the committed tree, not a stale local cache (cf. issue 004,
which WAS a harness artefact — this one is not).

## Observed (black-box, X01)

- `cargo test --workspace --all-targets --locked` (X01 runner) → exit 101, the
  lock error above, before any compilation.
- Blast radius: the `Dockerfile.query-api` / `log-query-api` / `trace-query-api`
  builds use `cargo build --release --locked`, so Q/LQ/TQ expectations cannot
  rebuild the image at `cdccb51`; the `cargo test --workspace --lib --locked`
  pre-commit hook fails on this tree too.

## How it passed the local gate

Committed-tree-vs-working-tree. A normal `cargo build`/`cargo test` (without
`--locked`, or with a writable lock) updates `Cargo.lock` in the working tree,
so the implementer's local hook, tests, and mutation run all passed against a
consistent working-tree lock. The committed tree shipped only a partial lock
update, so the published `cdccb51` is inconsistent. The pre-commit hook runs
against the working tree, so an uncommitted-but-present lock update masks the
broken committed state.

## What would make X01 pass

Commit a `Cargo.lock` consistent with the `cdccb51` manifests (`cargo build`
then commit the full lock delta), so `cargo build/test --workspace --locked`
succeeds. The fix shape is the implementer's; X01 flips GREEN on a consistent
lock.

## Scope note (verifier)

Reported as observable behaviour: the committed tree fails a `--locked` build.
Distinct from the feature's logic (the read-path-auth code may be correct — it
cannot be black-box-verified until the tree builds). The slice-1 binary-wiring
scope question (composition.rs does not yet resolve `KALEIDOSCOPE_QUERY_AUTH_*`,
so the auth path is not reachable through the deployed binary) is a separate,
non-blocking observation raised to the implementer, not asserted as a defect on
an in-progress sliced feature.
