#!/usr/bin/env bash
# run-loom.sh — shared driver for L-prefix runners.
#
# Builds the Loom binary inside rust:1.88-slim-bookworm against
# the HEAD snapshot, then invokes a per-runner inline script that
# does whatever the scenario needs (build fixtures, run the
# binary, capture exit + stdout + stderr). The inline script must
# be self-contained bash; it runs under `bash -c` after the build
# step has produced `/src/target/release/loom`.
#
# Args:
#   $1 = EVIDENCE_DIR (passed in by run-expectation.sh)
#   $2 = label (used for log filenames inside EVIDENCE_DIR)
#   $3 = inline bash script (single string)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" "$CACHE_DIR/target"

echo "step 1: build loom (cache hit if no source change) + run scenario"
docker run --rm \
    -v "$SNAPSHOT_DIR:/src:rw" \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/target:/src/target:rw" \
    -e CARGO_PROFILE_DEV_DEBUG=0 \
    -e CARGO_PROFILE_TEST_DEBUG=0 \
    -w /src \
    rust:1.88-slim-bookworm \
    bash -c "
        set -euo pipefail
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates >/dev/null
        rm -rf /var/lib/apt/lists/*
        cargo build --release -p loom --locked >&2
        LOOM=/src/target/release/loom
        ${INLINE_SCRIPT}
    " \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
