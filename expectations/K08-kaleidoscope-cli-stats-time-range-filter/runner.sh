#!/usr/bin/env bash
# K08 — `stats --since <ISO> --until <ISO>` filters the records= /
# earliest= / latest= lines (Lumen side) to the window; Cinder
# per-tier lines are state-snapshot and ignore the window.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"a","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000060000000000,"severity_number":9,"severity_text":"INFO","body":"b","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000120000000000,"severity_number":9,"severity_text":"INFO","body":"c","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" stats acme /data > /tmp/all.out 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" stats acme /data --since 2023-11-14T22:14:00Z --until 2023-11-14T22:14:30Z > /tmp/win.out 2>&1
echo "---all---"
cat /tmp/all.out
echo "---window---"
cat /tmp/win.out
cp /tmp/all.out "'"$EVIDENCE_DIR"'/stats-all.out"
cp /tmp/win.out "'"$EVIDENCE_DIR"'/stats-window.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K08 "$INLINE"

grep -q '^records=3$' "$EVIDENCE_DIR/stats-all.out"    || { echo "all: missing records=3" >&2; exit 1; }
grep -q '^records=1$' "$EVIDENCE_DIR/stats-window.out" || { echo "win: missing records=1" >&2; exit 1; }
echo "OK — stats --since/--until narrows the Lumen records count from 3 to 1"
