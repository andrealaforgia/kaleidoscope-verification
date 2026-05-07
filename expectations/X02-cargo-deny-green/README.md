# X02 — cargo-deny-green

## Surface

Operations / supply chain. Build-engineer-facing.

## Behaviour

`cargo deny --all-features check` exits green at HEAD: `advisories
ok, bans ok, licenses ok, sources ok`. Covers Gate 4 of the CI
contract per ADR-0005.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **X2**.
- External contract anchor:
  [`deny.toml`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/deny.toml)
  plus
  [`docs/product/architecture/adr-0005-ci-contract.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0005-ci-contract.md)
  Gate 4.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-07 UTC at HEAD.
- Method: two-step. Step 1 installs the latest `cargo-deny` (no
  version pin, mirroring the kaleidoscope CI which uses
  `taiki-e/install-action` to pull the latest binary release);
  install dir cached at `harness/.workspace-build-cache/cargo-install/`.
  Step 2 runs `cargo deny --all-features check` against the
  snapshot with `git` installed in-container so cargo-deny can clone
  the RustSec advisory database at `/usr/local/cargo/advisory-dbs/`
  (also cached). Assertion: docker run exits 0 (cargo-deny exit
  code) plus a defensive grep for the canonical summary line
  `advisories ok|all checks passed|no issues`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/cargo-deny-install.txt`](evidence/cargo-deny-install.txt) — installed version (`cargo-deny 0.19.4` at re-verification time).
- [`evidence/cargo-deny.stdout.txt`](evidence/cargo-deny.stdout.txt) — full check output. Final line is the green summary; intermediate `warning[license-not-encountered]` lines for `CC0-1.0`, `MPL-2.0`, `Unicode-DFS-2016`, `Zlib` are non-fatal allowance-not-encountered warnings.
- [`evidence/cargo-deny.stderr.txt`](evidence/cargo-deny.stderr.txt) — apt-get noise.

## Issues

None.

## Notes

Two ecosystem-drift findings during the first verification, both
fixed by tracking what kaleidoscope's CI does:

1. cargo-deny 0.16.4 errored on `RUSTSEC-2026-0037` (quinn-proto)
   with "unsupported CVSS version: 4.0". Newer cargo-deny releases
   parse CVSS 4.0 strings; the runner pulls the latest via
   `cargo install --locked cargo-deny`.
2. The base `rust:1.88-slim-bookworm` image lacks `git`;
   cargo-deny needs it to clone the RustSec advisory database.
   The runner now installs `git` in-container.
