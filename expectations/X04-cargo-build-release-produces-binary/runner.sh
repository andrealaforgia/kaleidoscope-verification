#!/usr/bin/env bash
# X04 — `cargo build --workspace --release` produces an executable
# `aperture` binary. We do not reuse the harness compose stack here
# (its Dockerfile builds only `-p aperture`); X04 is the workspace-
# wide invariant so we run a fresh `cargo build --workspace
# --release --locked` against the HEAD snapshot, then file-test the
# resulting binary.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    echo "snapshot dir missing: $SNAPSHOT_DIR" >&2
    exit 1
fi

# Persistent caches across X-prefix runs so the second run is fast.
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" "$CACHE_DIR/target"

echo "step 1: cargo build --workspace --release --locked (host arch arm64)"
docker run --rm \
    -v "$SNAPSHOT_DIR:/src:rw" \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/target:/src/target:rw" \
    -w /src \
    rust:1.88-slim-bookworm \
    bash -c '
        set -euo pipefail
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates >/dev/null
        rm -rf /var/lib/apt/lists/*
        echo "--- rustc / cargo versions ---"
        rustc --version
        cargo --version
        echo "--- cargo build --workspace --release --locked ---"
        cargo build --workspace --release --locked
        echo "--- target/release listing (top-level) ---"
        ls -la target/release | head -30
        echo "--- aperture binary check ---"
        if [[ -x target/release/aperture ]]; then
            stat -c "size=%s mode=%A path=%n" target/release/aperture
            ls -la target/release/aperture
            echo "PRESENT_AND_EXECUTABLE"
        else
            echo "ABSENT_OR_NOT_EXECUTABLE"
            exit 1
        fi
    ' \
    > "$EVIDENCE_DIR/cargo-build.stdout.txt" \
    2> "$EVIDENCE_DIR/cargo-build.stderr.txt"

echo "  cargo build done"

# Surface the most relevant lines.
echo "step 2: surface evidence"
echo "  rustc/cargo:"
grep -E "rustc |cargo " "$EVIDENCE_DIR/cargo-build.stdout.txt" | head -5 | sed 's/^/    /'
echo "  aperture binary:"
grep -A1 "binary check" "$EVIDENCE_DIR/cargo-build.stdout.txt" | tail -2 | sed 's/^/    /' || true

# 3. Assert the binary was built and reported as executable.
if ! grep -q "PRESENT_AND_EXECUTABLE" "$EVIDENCE_DIR/cargo-build.stdout.txt"; then
    echo "aperture binary not found at target/release/aperture" >&2
    exit 1
fi

echo "OK — cargo build --workspace --release produced an executable aperture binary"
