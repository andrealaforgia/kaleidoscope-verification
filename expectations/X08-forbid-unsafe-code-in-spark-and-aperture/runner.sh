#!/usr/bin/env bash
# X08 — Static check that #![forbid(unsafe_code)] is present at the
# crate root of both spark and aperture, read from the snapshot
# (HEAD), not the working tree.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT="$HARNESS_DIR/.snapshot"

{
    echo "=== crates/spark/src/lib.rs ==="
    grep -nE 'forbid.*unsafe_code' "$SNAPSHOT/crates/spark/src/lib.rs" || echo "(absent)"
    echo ""
    echo "=== crates/aperture/src/lib.rs ==="
    grep -nE 'forbid.*unsafe_code' "$SNAPSHOT/crates/aperture/src/lib.rs" || echo "(absent)"
} > "$EVIDENCE_DIR/citations.txt"

cat "$EVIDENCE_DIR/citations.txt"

fail=0
grep -qE 'forbid.*unsafe_code' "$SNAPSHOT/crates/spark/src/lib.rs" \
    || { echo "spark/src/lib.rs lacks forbid(unsafe_code)" >&2; fail=1; }
grep -qE 'forbid.*unsafe_code' "$SNAPSHOT/crates/aperture/src/lib.rs" \
    || { echo "aperture/src/lib.rs lacks forbid(unsafe_code)" >&2; fail=1; }
(( fail == 0 )) || exit 1

echo "OK — forbid(unsafe_code) present in spark and aperture"
