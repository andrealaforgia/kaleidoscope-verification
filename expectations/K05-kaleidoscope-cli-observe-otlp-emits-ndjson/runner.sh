#!/usr/bin/env bash
# K05 — `ingest --observe-otlp <path>` writes at least one
# NDJSON OTLP-JSON metric line to the given path per batch flush.
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
# Mount $DATA_HOST at /data; observe-otlp file lives there so we can read it back.
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data --observe-otlp /data/observed.ndjson < "$INPUT" > /tmp/out.txt 2>&1 || EC=$?
echo "exit=$EC"
echo "---observed file size + head---"
wc -c < "$DATA_HOST/observed.ndjson"
head -1 "$DATA_HOST/observed.ndjson" | head -c 400
echo
cp "$DATA_HOST/observed.ndjson" "'"$EVIDENCE_DIR"'/observed.ndjson"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K05 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/K05.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" == "0" ]] || { echo "ingest exit $EC" >&2; exit 1; }
[[ -s "$EVIDENCE_DIR/observed.ndjson" ]] || { echo "observed.ndjson empty" >&2; exit 1; }
# Must look like JSON containing "resourceMetrics" (the OTLP-JSON metric shape).
# NDJSON shape is one ResourceMetrics object per line, not a full
# ExportMetricsServiceRequest wrapper. Accept either form.
grep -qE 'resourceMetrics|scopeMetrics' "$EVIDENCE_DIR/observed.ndjson" || \
    { echo "observed file does not look like OTLP-JSON metrics" >&2; head -1 "$EVIDENCE_DIR/observed.ndjson" >&2; exit 1; }
echo "OK — --observe-otlp wrote NDJSON OTLP-JSON metrics to the configured path"
