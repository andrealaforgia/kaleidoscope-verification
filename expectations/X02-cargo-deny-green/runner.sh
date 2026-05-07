#!/usr/bin/env bash
# X02 — `cargo deny --all-features check` is green at HEAD. Covers
# Gate 4 (licence + advisory + bans) per ADR-0005.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" "$CACHE_DIR/cargo-install" "$CACHE_DIR/target"

# CARGO_INSTALL_ROOT is mounted as a separate host volume so the
# cargo-deny binary persists between runs. Putting it under
# /usr/local/cargo/bin would shadow the rust toolchain bins.

echo "step 1: ensure cargo-deny installed (cached install dir)"
docker run --rm \
    -v "$SNAPSHOT_DIR:/src:ro" \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/cargo-install:/cache/cargo-install:rw" \
    -e CARGO_INSTALL_ROOT=/cache/cargo-install \
    rust:1.88-slim-bookworm \
    bash -c '
        set -euo pipefail
        if ! /cache/cargo-install/bin/cargo-deny --version >/dev/null 2>&1; then
            apt-get update >/dev/null
            apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates git >/dev/null
            rm -rf /var/lib/apt/lists/*
            cargo install --locked cargo-deny
        fi
        /cache/cargo-install/bin/cargo-deny --version
    ' \
    > "$EVIDENCE_DIR/cargo-deny-install.txt" \
    2>&1

echo "  cargo-deny: $(tail -1 "$EVIDENCE_DIR/cargo-deny-install.txt")"

echo "step 2: cargo deny --all-features check"
# git is needed because cargo-deny clones the RustSec advisory
# database via libgit2 (or the system git CLI) at every check.
docker run --rm \
    -v "$SNAPSHOT_DIR:/src:ro" \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/cargo-install:/cache/cargo-install:rw" \
    -v "$CACHE_DIR/advisory-dbs:/usr/local/cargo/advisory-dbs:rw" \
    -e CARGO_INSTALL_ROOT=/cache/cargo-install \
    -e PATH=/cache/cargo-install/bin:/usr/local/cargo/bin:/usr/bin:/bin \
    -w /src \
    rust:1.88-slim-bookworm \
    bash -c '
        set -euo pipefail
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends git ca-certificates >/dev/null
        rm -rf /var/lib/apt/lists/*
        cargo deny --all-features check 2>&1
    ' \
    > "$EVIDENCE_DIR/cargo-deny.stdout.txt" \
    2> "$EVIDENCE_DIR/cargo-deny.stderr.txt"

echo "  exit: 0 (otherwise the docker run above would have failed)"
echo "  last 12 lines of cargo deny output:"
tail -12 "$EVIDENCE_DIR/cargo-deny.stdout.txt" | sed 's/^/    /'

# Sanity-check: deny prints `<check> ok, ...` summaries on success.
# The docker run above exits non-zero on cargo-deny failure (set -e
# inside the heredoc), so reaching here already means a green pass;
# the summary regex is just defensive.
if ! grep -qiE 'advisories ok|all checks passed|0 errors|no issues' "$EVIDENCE_DIR/cargo-deny.stdout.txt"; then
    echo "cargo deny output does not include a clean-summary marker; check evidence" >&2
    exit 1
fi

echo "OK — cargo deny --all-features check is green"
