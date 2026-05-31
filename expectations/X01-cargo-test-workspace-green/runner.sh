#!/usr/bin/env bash
# X01 — `cargo test --workspace --all-targets --locked` is green on
# the kaleidoscope HEAD snapshot. Runs inside the project-pinned
# rust:1.88-slim-bookworm image with persistent registry / target
# caches under harness/.workspace-build-cache/.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" "$CACHE_DIR/target"

echo "step 1: cargo test --workspace --all-targets --locked"
# CARGO_PROFILE_TEST_DEBUG=0 suppresses debuginfo in test binaries.
# Without it, linking the slice_05 test binary in spark/sieve OOM-kills
# `ld` under Docker Desktop's default macOS memory cap (~2-4 GB
# allocated to the Linux VM). The contract being verified is "tests
# run green"; debuginfo presence is orthogonal to that. CI runs with
# default debuginfo because GitHub Actions runners have more memory.
#
# CARGO_BUILD_JOBS=1 serialises codegen. Under the same ~2-4 GB VM cap,
# a parallel `--all-targets` codegen race OOM-kills rustc subprocesses
# mid-compile, leaving partial rlibs; dependents then fail with E0463
# "can't find crate for <X>" even for crates that themselves reached
# "Compiling ..." (and even for a crate's OWN test target). That false
# signal was filed as issue 004 and broke X01/X05. The 2026-05-31
# cross-check with Bea Implementer (clean `cargo build -p self-observe`
# = 7.18s exit 0 on her side) plus a -j1 diagnostic here (full
# `--workspace --all-targets --locked` GREEN) proved it a harness
# resource artefact, not a kaleidoscope defect. Serialising fixes it;
# X01 is an occasional X-prefix run, so correctness beats speed.
docker run --rm \
    -v "$SNAPSHOT_DIR:/src:rw" \
    -v "$CACHE_DIR/cargo-registry:/usr/local/cargo/registry:rw" \
    -v "$CACHE_DIR/cargo-git:/usr/local/cargo/git:rw" \
    -v "$CACHE_DIR/target:/src/target:rw" \
    -e CARGO_PROFILE_TEST_DEBUG=0 \
    -e CARGO_PROFILE_DEV_DEBUG=0 \
    -e CARGO_BUILD_JOBS=1 \
    -w /src \
    rust:1.88-slim-bookworm \
    bash -c '
        set -euo pipefail
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates >/dev/null
        rm -rf /var/lib/apt/lists/*
        rustc --version
        cargo --version
        cargo test --workspace --all-targets --locked 2>&1
    ' \
    > "$EVIDENCE_DIR/cargo-test.stdout.txt" \
    2> "$EVIDENCE_DIR/cargo-test.stderr.txt"

# Surface key signals from the output.
echo "step 2: surface evidence"
echo "  rustc/cargo:"
grep -E '^(rustc|cargo) ' "$EVIDENCE_DIR/cargo-test.stdout.txt" | sed 's/^/    /'
echo "  test totals (last 6 'test result:' lines):"
grep -E '^test result:' "$EVIDENCE_DIR/cargo-test.stdout.txt" | tail -6 | sed 's/^/    /'

# Assertions: every `test result:` line must be `ok`. Cargo's exit
# code is also captured at the docker run level (via set -e + the
# heredoc).
if grep -E '^test result:' "$EVIDENCE_DIR/cargo-test.stdout.txt" | grep -qv ' ok\.'; then
    echo "at least one 'test result:' line was not 'ok'" >&2
    exit 1
fi

# Match cargo's ACTUAL failure markers, anchored at line start, NOT a
# bare 'FAILED|test failed' which false-positives on a passing test
# whose NAME contains the word (e.g.
# `failed_cinder_migrate_emits_no_otlp_line ... ok`). Real failures are
# `test result: FAILED.`, `error: test failed`, or a compile error.
if grep -qE '^test result: FAILED|^error: test failed|^error(\[|: could not compile)' \
        "$EVIDENCE_DIR/cargo-test.stdout.txt"; then
    echo "saw a real cargo failure marker (test result: FAILED / error: test failed / compile error)" >&2
    exit 1
fi

echo "OK — cargo test --workspace --all-targets --locked is green"
