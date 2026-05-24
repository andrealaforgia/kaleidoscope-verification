#!/usr/bin/env bash
# K12 — `ingest --observe-otlp <path>` writes BOTH a Lumen metric
# (`lumen.ingest.count`) AND a Cinder metric (`cinder.*`) line
# to the same NDJSON file. Anchors the cross-writer wiring from
# commit 2baa05c ("wire Cinder events into --observe-otlp sink").
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":100,"severity_number":9,"severity_text":"INFO","body":"event a","attributes":{},"resource_attributes":{"service.name":"svc"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":200,"severity_number":9,"severity_text":"INFO","body":"event b","attributes":{},"resource_attributes":{"service.name":"svc"},"trace_id":null,"span_id":null}
JSON
EC=0
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data --observe-otlp /data/observed.ndjson < "$INPUT" > /tmp/out.txt 2>&1 || EC=$?
echo "exit=$EC"
echo "---observed file size + head---"
wc -c < "$DATA_HOST/observed.ndjson"
head -5 "$DATA_HOST/observed.ndjson"
cp "$DATA_HOST/observed.ndjson" "'"$EVIDENCE_DIR"'/observed.ndjson"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K12 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/K12.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" == "0" ]] || { echo "ingest exit $EC" >&2; exit 1; }
[[ -s "$EVIDENCE_DIR/observed.ndjson" ]] || { echo "observed.ndjson empty" >&2; exit 1; }

# Hard equality: extract metric names structurally and assert
# coexistence of `lumen.ingest.count` and at least one `cinder.*`.
NAMES=$(grep '^{' "$EVIDENCE_DIR/observed.ndjson" \
    | jq -r '.scopeMetrics[]?.metrics[]?.name' 2>/dev/null \
    | sort -u)
echo "$NAMES" | grep -qx "lumen.ingest.count" || {
    echo "observed file lacks lumen.ingest.count metric; got:" >&2
    echo "$NAMES" >&2
    exit 1
}
echo "$NAMES" | grep -qE '^cinder\.' || {
    echo "observed file lacks any cinder.* metric (cross-writer wiring absent); got:" >&2
    echo "$NAMES" >&2
    exit 1
}
echo "OK — observe-otlp sink contains BOTH lumen.ingest.count AND a cinder.* metric (structural)"
