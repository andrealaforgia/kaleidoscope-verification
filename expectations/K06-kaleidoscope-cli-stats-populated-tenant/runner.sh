#!/usr/bin/env bash
# K06 — After ingesting N records for a tenant, `stats <tenant> <dir>`
# emits records=N plus `earliest=<ISO>` and `latest=<ISO>` lines.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"first","attributes":{},"resource_attributes":{"service.name":"svc"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000060000000000,"severity_number":9,"severity_text":"INFO","body":"second","attributes":{},"resource_attributes":{"service.name":"svc"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000120000000000,"severity_number":9,"severity_text":"INFO","body":"third","attributes":{},"resource_attributes":{"service.name":"svc"},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" >/tmp/ingest.out 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" stats acme /data > /tmp/stats.out 2>&1
echo "---stats output---"
cat /tmp/stats.out
cp /tmp/stats.out "'"$EVIDENCE_DIR"'/stats.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K06 "$INLINE"

grep -q '^records=3$' "$EVIDENCE_DIR/stats.out" || { echo "missing records=3" >&2; exit 1; }
grep -q '^earliest=' "$EVIDENCE_DIR/stats.out" || { echo "missing earliest=" >&2; exit 1; }
grep -q '^latest='   "$EVIDENCE_DIR/stats.out" || { echo "missing latest="   >&2; exit 1; }
echo "OK — stats emits records=3 + earliest + latest for a populated tenant"
