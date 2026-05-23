#!/usr/bin/env bash
# K09 — After ingesting, `stats` emits at least the `hot=N` line
# (Cinder Hot tier placement; commit 946d2c8). Warm/cold lines
# only appear when those tiers are non-zero.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"x","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000060000000000,"severity_number":9,"severity_text":"INFO","body":"y","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" stats acme /data > /tmp/stats.out 2>&1
echo "---stats output---"
cat /tmp/stats.out
cp /tmp/stats.out "'"$EVIDENCE_DIR"'/stats.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K09 "$INLINE"

grep -qE '^hot=[1-9][0-9]*$' "$EVIDENCE_DIR/stats.out" || \
    { echo "missing hot=N line in stats output" >&2; exit 1; }
echo "OK — stats emits Cinder hot=N line after ingest"
