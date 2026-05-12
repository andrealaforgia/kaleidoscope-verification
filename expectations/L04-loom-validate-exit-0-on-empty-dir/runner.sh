#!/usr/bin/env bash
# L04 — `loom validate --rules <empty-dir>` exits 0.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
mkdir -p /tmp/empty-fixture
EC=0
$LOOM validate --rules /tmp/empty-fixture || EC=$?
echo "exit=$EC"
'
"$HARNESS_DIR/run-loom.sh" "$EVIDENCE_DIR" L04 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/L04.stdout.txt" | tail -1 | cut -d= -f2)
echo "  loom validate exit: $EC"
if [[ "$EC" != "0" ]]; then echo "expected 0, got $EC" >&2; exit 1; fi
echo "OK — loom validate exited 0 on empty directory"
