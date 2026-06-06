#!/usr/bin/env bash
# K28 — `stats` over an empty (or unknown) tenant reports `records=0`
# and emits NO `earliest=`/`latest=` lines. Covers UC-RANGE-005.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
# Query stats for a tenant that was never ingested into a fresh dir.
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" stats ghosttenant /data \
    > /tmp/stats.out 2>&1
echo "stats-exit=$?" > /tmp/stats.rc
echo "---stats (empty tenant)---"; cat /tmp/stats.rc; cat /tmp/stats.out
cp /tmp/stats.out "'"$EVIDENCE_DIR"'/stats.out"; cp /tmp/stats.rc "'"$EVIDENCE_DIR"'/stats.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K28 "$INLINE"

grep -qx 'records=0' "$EVIDENCE_DIR/stats.out" || { echo "empty tenant did not report records=0" >&2; exit 1; }
grep -qE '^(earliest|latest)=' "$EVIDENCE_DIR/stats.out" && { echo "empty tenant emitted earliest/latest lines (should not)" >&2; exit 1; }
echo "OK — empty tenant stats: records=0, no earliest/latest lines"
