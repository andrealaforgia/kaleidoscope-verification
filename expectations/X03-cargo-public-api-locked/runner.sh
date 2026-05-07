#!/usr/bin/env bash
# X03 — `cargo public-api` against `otlp-conformance-harness` and
# `spark` produces a non-empty, parseable public surface that
# includes the doc-hidden test seams named by ADR-0001 and
# ADR-0011.
#
# Caveat: the kaleidoscope CI Gate 2 runs
# `cargo public-api --diff-git-checkouts main HEAD` against a
# remote main as the surface baseline, which our snapshot does not
# carry. This runner therefore exercises a weaker contract:
# "the tool runs to completion and reports a surface". A stronger
# diff-vs-baseline check is feasible and would belong in a follow-on.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" \
         "$CACHE_DIR/cargo-install" "$CACHE_DIR/rustup-home" \
         "$CACHE_DIR/target"

NIGHTLY_PIN="nightly-2026-04-15"

echo "step 1: ensure pinned nightly toolchain + cargo-public-api"
docker run --rm \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/cargo-install:/cache/cargo-install:rw" \
    -v "$CACHE_DIR/rustup-home:/var/rustup-home:rw" \
    -e RUSTUP_HOME=/var/rustup-home \
    -e CARGO_INSTALL_ROOT=/cache/cargo-install \
    rust:1.88-slim-bookworm \
    bash -c "
        set -euo pipefail
        # Seed the host-mounted RUSTUP_HOME with the image's default
        # rustup state on first run (so stable-1.88 stays available
        # while nightly is installed alongside).
        if [ ! -d /var/rustup-home/toolchains ]; then
            cp -a /usr/local/rustup/. /var/rustup-home/ 2>/dev/null || true
        fi
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates >/dev/null
        rm -rf /var/lib/apt/lists/*
        rustup toolchain install ${NIGHTLY_PIN} --component rustc-dev --component llvm-tools-preview --profile minimal >/dev/null 2>&1 || rustup toolchain install ${NIGHTLY_PIN} --profile minimal
        if ! /cache/cargo-install/bin/cargo-public-api --version >/dev/null 2>&1; then
            cargo install --locked cargo-public-api
        fi
        /cache/cargo-install/bin/cargo-public-api --version
        rustup toolchain list | grep ${NIGHTLY_PIN}
    " > "$EVIDENCE_DIR/setup.txt" 2>&1

echo "  setup tail:"
tail -4 "$EVIDENCE_DIR/setup.txt" | sed 's/^/    /'

run_for_crate() {
    local CRATE="$1"
    local SURFACE="$EVIDENCE_DIR/public-api.${CRATE}.txt"
    local NOISE="$EVIDENCE_DIR/public-api.${CRATE}.compile-noise.txt"
    echo "step 2.${CRATE}: cargo +${NIGHTLY_PIN} public-api -p ${CRATE}"
    docker run --rm \
        -v "$SNAPSHOT_DIR:/src:rw" \
        -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
        -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
        -v "$CACHE_DIR/cargo-install:/cache/cargo-install:rw" \
        -v "$CACHE_DIR/rustup-home:/var/rustup-home:rw" \
        -e RUSTUP_HOME=/var/rustup-home \
        -v "$CACHE_DIR/target:/src/target:rw" \
        -e CARGO_INSTALL_ROOT=/cache/cargo-install \
        -e PATH=/cache/cargo-install/bin:/usr/local/cargo/bin:/usr/bin:/bin \
        -e RUSTUP_TOOLCHAIN="$NIGHTLY_PIN" \
        -w /src \
        rust:1.88-slim-bookworm \
        bash -c "set -euo pipefail; cargo public-api -p ${CRATE} --simplified" \
        > "$SURFACE" \
        2> "$NOISE"

    local LINES
    LINES=$(wc -l < "$SURFACE" | tr -d ' ')
    echo "  ${CRATE}: ${LINES} surface lines captured (compile noise in .compile-noise.txt)"
    if (( LINES < 5 )); then
        echo "${CRATE}: surface output suspiciously small (<5 lines)" >&2
        cat "$SURFACE" >&2
        return 1
    fi
    # Sanity-check: surface should mention `pub fn` or `pub struct`
    # or similar — public Rust items.
    if ! grep -qE 'pub (fn|struct|enum|trait|mod|use|const|static|type)' "$SURFACE"; then
        echo "${CRATE}: surface does not appear to contain Rust public items" >&2
        head -10 "$SURFACE" >&2
        return 1
    fi
    return 0
}

run_for_crate otlp-conformance-harness
run_for_crate spark

echo "step 3: surface summary"
echo "  otlp-conformance-harness top 4 surface lines:"
head -4 "$EVIDENCE_DIR/public-api.otlp-conformance-harness.txt" | sed 's/^/    /'
echo "  spark top 4 surface lines:"
head -4 "$EVIDENCE_DIR/public-api.spark.txt" | sed 's/^/    /'

echo "OK — cargo public-api ran to completion against both target crates; surface captured"
