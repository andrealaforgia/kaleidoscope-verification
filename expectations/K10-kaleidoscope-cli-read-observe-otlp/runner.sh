#!/usr/bin/env bash
# K10 — `read --observe-otlp <path>` appends one OTLP-JSON line
# carrying `lumen.query.count` per invocation.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"hello","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data --observe-otlp /data/observed.ndjson > /tmp/read.out 2>&1
echo "---observed head---"
head -1 "$DATA_HOST/observed.ndjson" | head -c 500
echo
cp "$DATA_HOST/observed.ndjson" "'"$EVIDENCE_DIR"'/observed.ndjson"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K10 "$INLINE"

# Hard equality: extract the metric `.name` field across NDJSON
# resourceMetrics records and assert `lumen.query.count` is among
# them. Substring grep would also accept the name appearing in any
# resource attribute value.
NAMES=$(grep '^{' "$EVIDENCE_DIR/observed.ndjson" \
    | jq -r '.scopeMetrics[]?.metrics[]?.name' 2>/dev/null \
    | sort -u)
echo "$NAMES" | grep -qx "lumen.query.count" || {
    echo "observed file lacks lumen.query.count as a metric name; got:" >&2
    echo "$NAMES" >&2
    exit 1
}
echo "OK — read --observe-otlp emits a metric named lumen.query.count (structural)"
