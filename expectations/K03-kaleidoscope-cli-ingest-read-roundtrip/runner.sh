#!/usr/bin/env bash
# K03 — Pipe NDJSON LogRecord lines through `ingest`, then run
# `read` against the same data dir; the records come back.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":100,"severity_number":9,"severity_text":"INFO","body":"first event","attributes":{},"resource_attributes":{"service.name":"checkout"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":200,"severity_number":9,"severity_text":"INFO","body":"second event","attributes":{},"resource_attributes":{"service.name":"checkout"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":300,"severity_number":17,"severity_text":"ERROR","body":"third event","attributes":{"http.status_code":"500"},"resource_attributes":{"service.name":"checkout"},"trace_id":null,"span_id":null}
JSON
EC_INGEST=0
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" > /tmp/ingest.out 2>&1 || EC_INGEST=$?
echo "ingest-exit=$EC_INGEST"
echo "---ingest output---"
cat /tmp/ingest.out
EC_READ=0
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data > /tmp/read.out 2> /tmp/read.err || EC_READ=$?
echo "read-exit=$EC_READ"
LINES=$(wc -l < /tmp/read.out | tr -d " ")
echo "read-lines=$LINES"
cp /tmp/read.out "'"$EVIDENCE_DIR"'/read-output.ndjson"
cp /tmp/ingest.out "'"$EVIDENCE_DIR"'/ingest-output.txt"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K03 "$INLINE"

EC_I=$(grep -oE 'ingest-exit=[0-9]+' "$EVIDENCE_DIR/K03.stdout.txt" | cut -d= -f2)
EC_R=$(grep -oE 'read-exit=[0-9]+'   "$EVIDENCE_DIR/K03.stdout.txt" | cut -d= -f2)
[[ "$EC_I" == "0" ]] || { echo "ingest failed" >&2; exit 1; }
[[ "$EC_R" == "0" ]] || { echo "read failed"  >&2; exit 1; }

# Hard equality: extract the .body field from each NDJSON record
# (skip the `read ok: records=N` diagnostic line) and compare the
# sorted set against the input set exactly. A substring grep would
# accept "first event" landing in any field; this asserts it
# landed in `.body`, the contract LogRecord body field.
ACTUAL=$(grep '^{' "$EVIDENCE_DIR/read-output.ndjson" | jq -r '.body' | sort)
EXPECTED=$(printf '%s\n' "first event" "second event" "third event" | sort)
[[ "$ACTUAL" == "$EXPECTED" ]] || {
    echo "body set mismatch:" >&2
    diff <(echo "$EXPECTED") <(echo "$ACTUAL") >&2 || true
    exit 1
}
echo "OK — ingest + read round-trip preserves all 3 records (.body exact-equality)"
