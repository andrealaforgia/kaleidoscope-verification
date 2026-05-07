#!/usr/bin/env bash
# X05 — `scripts/hooks/pre-commit` runs the local quality gates
# (fmt, clippy, deny, cargo test) and exits 0 on a clean
# workspace. Mirrors what kaleidoscope contributors run before
# every commit per ADR-0005's CI contract.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" \
         "$CACHE_DIR/cargo-install" "$CACHE_DIR/target"

echo "step 1: ensure cargo-deny installed (Step 3 of the hook needs it)"
docker run --rm \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/cargo-install:/cache/cargo-install:rw" \
    -e CARGO_INSTALL_ROOT=/cache/cargo-install \
    rust:1.88-slim-bookworm \
    bash -c '
        if ! /cache/cargo-install/bin/cargo-deny --version >/dev/null 2>&1; then
            apt-get update >/dev/null
            apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates >/dev/null
            rm -rf /var/lib/apt/lists/*
            cargo install --locked cargo-deny
        fi
    ' >/dev/null 2>&1

echo "step 2: run scripts/hooks/pre-commit on the snapshot"
docker run --rm \
    -v "$SNAPSHOT_DIR:/src:rw" \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/cargo-install:/cache/cargo-install:rw" \
    -v "$CACHE_DIR/target:/src/target:rw" \
    -e CARGO_INSTALL_ROOT=/cache/cargo-install \
    -e PATH=/cache/cargo-install/bin:/usr/local/cargo/bin:/usr/bin:/bin \
    -e CARGO_PROFILE_TEST_DEBUG=0 \
    -e CARGO_PROFILE_DEV_DEBUG=0 \
    -w /src \
    rust:1.88-slim-bookworm \
    bash -c '
        set -euo pipefail
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates git >/dev/null 2>&1 || true
        rm -rf /var/lib/apt/lists/* || true
        rustup component add rustfmt clippy 2>&1 || true
        bash scripts/hooks/pre-commit 2>&1
    ' \
    > "$EVIDENCE_DIR/pre-commit.stdout.txt" \
    2> "$EVIDENCE_DIR/pre-commit.stderr.txt"

echo "  hook exited 0 (cleanly)"
echo "  last 15 lines of hook output:"
tail -15 "$EVIDENCE_DIR/pre-commit.stdout.txt" | sed 's/^/    /'

# Sanity-check: the hook ends with "[pass] all pre-commit gates green"
# on success.
if ! grep -q 'all pre-commit gates green' "$EVIDENCE_DIR/pre-commit.stdout.txt"; then
    echo "hook output lacks the success marker '[pass] all pre-commit gates green'" >&2
    exit 1
fi

echo "OK — pre-commit hook ran every local gate and exited 0"
