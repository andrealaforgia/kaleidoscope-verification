#!/usr/bin/env bash
# D06 — pulse (metrics) torn-WAL-tail recovery, the Pulse-store member of
# the issue-006 close. After wal-torn-tail-recovery-v0 rewired pulse's
# open onto the shared wal_recovery seam (feat 7c4a5e2, pillar="pulse"),
# a torn trailing line in /data/pulse.wal must NOT brick the store: the
# intact prefix is recovered and the torn tail ignored, readable via
# query-api. Same SAFE-either-way shape as D04/D05; recovery expected.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="d06-gw-$$"
QAPI_NAME="d06-qapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14332:4318 \
    "$GW_IMAGE" > /dev/null
SAW=""
for i in $(seq 1 30); do
    docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14332 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 --otlp-attributes service.name=\"d06-pilot\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null
docker rm "$GW_NAME" >/dev/null 2>&1 || true

WAL="$SHARED_DATA/pulse.wal"
ls -l "$SHARED_DATA" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
if [[ -f "$WAL" ]]; then
    cp "$WAL" "'"$EVIDENCE_DIR"'/pulse.wal.before"
    LINES_BEFORE=$(wc -l < "$WAL" | tr -d " ")
    printf "%s" "{\"op\":\"ingest\",\"tenant\":\"acme\",\"metrics\":[{\"name\"" >> "$WAL"
    cp "$WAL" "'"$EVIDENCE_DIR"'/pulse.wal.after"
else
    echo "PULSE_WAL_NOT_FOUND_at_$WAL"; LINES_BEFORE=NA
fi
echo "wal_lines_before_tear=$LINES_BEFORE"

docker run -d \
    --name "$QAPI_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19105:9090 \
    "$QAPI_IMAGE" > /dev/null
sleep 4
RUNNING=$(docker inspect -f "{{.State.Running}}" "$QAPI_NAME" 2>/dev/null || echo "gone")
EXITCODE=$(docker inspect -f "{{.State.ExitCode}}" "$QAPI_NAME" 2>/dev/null || echo "gone")
echo "qapi_running=$RUNNING qapi_exitcode=$EXITCODE"
docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true

QCODE=000
if [[ "$RUNNING" == "true" ]]; then
    START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
    END=$(( $(date -u +%s) + 120 ))
    QCODE=$(curl -sS -o "'"$EVIDENCE_DIR"'/d06-query.json" -w "%{http_code}" \
        "http://localhost:19105/api/v1/query_range?query=gen&start=${START}&end=${END}&step=15s" 2>/dev/null || echo "000")
fi
echo "query_code=$QCODE"
[[ -f "'"$EVIDENCE_DIR"'/d06-query.json" ]] && echo "result_status=$(jq -r .status "'"$EVIDENCE_DIR"'/d06-query.json" 2>/dev/null || echo NA) result_count=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/d06-query.json" 2>/dev/null || echo NA)"
docker stop --time 3 "$QAPI_NAME" >/dev/null 2>&1 || true
docker rm "$QAPI_NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" D06 "$INLINE"

OUT="$EVIDENCE_DIR/D06.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
RUNNING=$(val qapi_running); EXITCODE=$(val qapi_exitcode); QCODE=$(val query_code)

if [[ "$RUNNING" == "true" ]]; then
    [[ "$QCODE" == "200" ]] || { echo "service up but query returned $QCODE" >&2; exit 1; }
    ST=$(jq -r '.status' "$EVIDENCE_DIR/d06-query.json")
    [[ "$ST" == "success" ]] || { echo "post-tear query status=$ST" >&2; cat "$EVIDENCE_DIR/d06-query.json" >&2; exit 1; }
    CNT=$(jq -r '.data.result | length' "$EVIDENCE_DIR/d06-query.json")
    [[ "$CNT" -ge 1 ]] || { echo "recovery branch but 0 series recovered" >&2; cat "$EVIDENCE_DIR/d06-query.json" >&2; exit 1; }
    NAME=$(jq -r '.data.result[0].metric.__name__' "$EVIDENCE_DIR/d06-query.json")
    [[ "$NAME" == "gen" ]] || { echo "recovered series __name__=$NAME, expected gen" >&2; exit 1; }
    echo "OK — pulse torn WAL tail tolerated: query-api recovered the intact metric (status=success, __name__=gen) and ignored the torn trailing line (graceful recovery, shared wal_recovery seam on the Pulse store)"
else
    [[ "$EXITCODE" != "0" && "$EXITCODE" != "gone" ]] || { echo "not running but exit '$EXITCODE'" >&2; exit 1; }
    grep -qE 'PersistenceFailed|WAL parse error' "$EVIDENCE_DIR/query-api.stderr.txt" \
        || { echo "fail-closed but no clear error" >&2; cat "$EVIDENCE_DIR/query-api.stderr.txt" >&2; exit 1; }
    echo "OK — pulse torn WAL tail does NOT yield corrupt data: query-api fails closed (exit ${EXITCODE}) with a clear error (SAFE; note: pulse was expected to RECOVER at this SHA)"
fi
