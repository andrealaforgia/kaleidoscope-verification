#!/usr/bin/env bash
# X09 — `xtask/regenerate_codex_corpus` is idempotent on the
# committed corpus. Running the binary on a clean snapshot of HEAD
# must produce zero diff against `crates/codex/src/generated/semconv_0_27.rs`
# as committed.
#
# Per ADR-0023's load-bearing rationale: "nothing changes silently
# in CI; every corpus delta is a code review event". This
# expectation is the catch-net for that promise.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
GENERATED="crates/codex/src/generated/semconv_0_27.rs"
mkdir -p "$CACHE_DIR/cargo-registry" "$CACHE_DIR/cargo-git" "$CACHE_DIR/target"

# 1. Preserve the as-committed copy for diff later.
cp "$SNAPSHOT_DIR/$GENERATED" "$EVIDENCE_DIR/semconv_0_27.committed.rs"
echo "step 1: committed corpus size: $(wc -l < "$EVIDENCE_DIR/semconv_0_27.committed.rs") lines"

# 2. Run the regenerator inside the project-pinned toolchain.
echo "step 2: cargo run --package regenerate-codex-corpus"
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
        cargo run --release --package regenerate-codex-corpus --bin regenerate-codex-corpus 2>&1
    ' \
    > "$EVIDENCE_DIR/xtask.stdout.txt" \
    2> "$EVIDENCE_DIR/xtask.stderr.txt"

echo "  xtask exit 0; last 4 lines of output:"
tail -4 "$EVIDENCE_DIR/xtask.stdout.txt" | sed 's/^/    /'

# 3. Capture the regenerated artefact.
cp "$SNAPSHOT_DIR/$GENERATED" "$EVIDENCE_DIR/semconv_0_27.regenerated.rs"
echo "step 3: regenerated corpus size: $(wc -l < "$EVIDENCE_DIR/semconv_0_27.regenerated.rs") lines"

# 4. Diff committed vs regenerated.
echo "step 4: diff committed vs regenerated"
DIFF_FILE="$EVIDENCE_DIR/semconv_0_27.diff"
if diff -u "$EVIDENCE_DIR/semconv_0_27.committed.rs" \
            "$EVIDENCE_DIR/semconv_0_27.regenerated.rs" \
            > "$DIFF_FILE"; then
    echo "  zero diff (corpus is idempotent)"
else
    echo "  DIFF observed; see ${DIFF_FILE}" >&2
    head -20 "$DIFF_FILE" >&2
    exit 1
fi

echo "OK — xtask regenerate-codex-corpus produced no diff against the committed corpus"
