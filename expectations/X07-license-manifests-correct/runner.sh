#!/usr/bin/env bash
# X07 — Static read of each crate's Cargo.toml from the snapshot
# (NOT the working tree) and verbatim verify the license fields.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT="$HARNESS_DIR/.snapshot"

{
    echo "=== crates/otlp-conformance-harness/Cargo.toml ==="
    grep -nE '^license' "$SNAPSHOT/crates/otlp-conformance-harness/Cargo.toml"
    echo ""
    echo "=== crates/spark/Cargo.toml ==="
    grep -nE '^license' "$SNAPSHOT/crates/spark/Cargo.toml"
    echo ""
    echo "=== crates/aperture/Cargo.toml ==="
    grep -nE '^license' "$SNAPSHOT/crates/aperture/Cargo.toml"
} > "$EVIDENCE_DIR/citations.txt"

cat "$EVIDENCE_DIR/citations.txt"

# Assert: each crate has the expected license string.
fail=0
grep -q '^license = "Apache-2.0"' "$SNAPSHOT/crates/otlp-conformance-harness/Cargo.toml" \
    || { echo "otlp-conformance-harness: license != Apache-2.0" >&2; fail=1; }
grep -q '^license = "Apache-2.0"' "$SNAPSHOT/crates/spark/Cargo.toml" \
    || { echo "spark: license != Apache-2.0" >&2; fail=1; }
grep -q '^license = "AGPL-3.0-or-later"' "$SNAPSHOT/crates/aperture/Cargo.toml" \
    || { echo "aperture: license != AGPL-3.0-or-later" >&2; fail=1; }
(( fail == 0 )) || exit 1

echo "OK — license manifests match the contract"
