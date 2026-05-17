#!/usr/bin/env bash
# K04 — `ingest` exits non-zero with a ParseRecord diagnostic
# (naming the line number) when given a malformed NDJSON line.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/bad.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":100,"severity_number":9,"severity_text":"INFO","body":"good","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
this-is-not-json
JSON
EC=0
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" > /tmp/out.txt 2> /tmp/err.txt || EC=$?
echo "exit=$EC"
echo "---stderr head---"
head -5 /tmp/err.txt
cp /tmp/err.txt "'"$EVIDENCE_DIR"'/ingest.stderr.txt"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K04 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/K04.stdout.txt" | tail -1 | cut -d= -f2)
echo "  exit: $EC"
[[ "$EC" != "0" ]] || { echo "expected non-zero exit on malformed line" >&2; exit 1; }
grep -qiE "parse|line 2|invalid" "$EVIDENCE_DIR/ingest.stderr.txt" || \
    { echo "stderr lacks parse/line/invalid hint" >&2; exit 1; }
echo "OK — malformed NDJSON line is rejected (exit ${EC}, diagnostic on stderr)"
