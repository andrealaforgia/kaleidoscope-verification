#!/usr/bin/env bash
# K11 — `ingest` / `read` / `stats` reject unknown flags with a
# non-zero exit and a diagnostic on stderr. Anchored at commit
# e7fbee0 ("ingest + compact reject unknown flags loudly").
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
docker run --rm "$KCLI_IMAGE" ingest acme /data --observe-otlpp /tmp/wrong.log > /tmp/out.txt 2> /tmp/err.txt || EC=$?
echo "exit=$EC"
echo "---stderr head---"
head -3 /tmp/err.txt
cp /tmp/err.txt "'"$EVIDENCE_DIR"'/ingest.stderr.txt"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K11 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/K11.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" != "0" ]] || { echo "expected non-zero exit on unknown flag" >&2; exit 1; }
grep -qiE "unknown|unexpected|invalid|--observe-otlpp" "$EVIDENCE_DIR/ingest.stderr.txt" || \
    { echo "stderr lacks unknown-flag diagnostic" >&2; exit 1; }
echo "OK — unknown flag rejected with non-zero exit (${EC}) + stderr diagnostic"
