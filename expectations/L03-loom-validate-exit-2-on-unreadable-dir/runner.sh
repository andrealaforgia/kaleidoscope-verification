#!/usr/bin/env bash
# L03 — `loom validate --rules <missing>` exits 2 on unreadable / missing dir.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
$LOOM validate --rules /nonexistent-path || EC=$?
echo "exit=$EC"
'
"$HARNESS_DIR/run-loom.sh" "$EVIDENCE_DIR" L03 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/L03.stdout.txt" | tail -1 | cut -d= -f2)
echo "  loom validate exit: $EC"
if [[ "$EC" != "2" ]]; then echo "expected 2, got $EC" >&2; exit 1; fi
echo "OK — loom validate exited 2 on unreadable directory"
