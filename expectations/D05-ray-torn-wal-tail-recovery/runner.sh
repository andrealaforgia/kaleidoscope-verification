#!/usr/bin/env bash
# D05 — ray (traces) torn-WAL-tail recovery, the Ray-store sibling of
# D04. After wal-torn-tail-recovery-v0 rewired ray's open onto the
# shared wal_recovery seam (feat 188c6c2, pillar="ray"), a torn trailing
# line in the Ray WAL must NOT brick the store: the intact prefix is
# recovered and the torn tail ignored. As with D04, the runner accepts
# either SAFE shape — graceful recovery (running, 200, intact spans, no
# torn record) OR clean fail-closed with a clear error — and fails only
# on corrupt-data-served or a silent crash. At 188c6c2 the recovery
# branch is expected.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SERVICE="d05-pilot"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="d05-gw-$$"
TQ_NAME="d05-tqapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Ingest spans, stop the gateway CLEANLY so the Ray WAL holds only
#    well-formed lines.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14331:4318 \
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
    traces --otlp-endpoint localhost:14331 --otlp-insecure --otlp-http \
    --traces 5 --child-spans 1 --service "$SERVICE" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# 2. TEAR the Ray WAL tail: append an incomplete JSON line, no newline.
WAL="$SHARED_DATA/ray.wal"
ls -l "$SHARED_DATA" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
if [[ -f "$WAL" ]]; then
    cp "$WAL" "'"$EVIDENCE_DIR"'/ray.wal.before"
    LINES_BEFORE=$(wc -l < "$WAL" | tr -d " ")
    printf "%s" "{\"op\":\"ingest\",\"tenant\":\"acme\",\"spans\":[{\"trace_id\"" >> "$WAL"
    cp "$WAL" "'"$EVIDENCE_DIR"'/ray.wal.after"
else
    echo "RAY_WAL_NOT_FOUND_at_$WAL"; LINES_BEFORE=NA
fi
echo "wal_lines_before_tear=$LINES_BEFORE"

# 3. Start trace-query-api on the torn /data; observe open + query.
docker run -d \
    --name "$TQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19104:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 4
RUNNING=$(docker inspect -f "{{.State.Running}}" "$TQ_NAME" 2>/dev/null || echo "gone")
EXITCODE=$(docker inspect -f "{{.State.ExitCode}}" "$TQ_NAME" 2>/dev/null || echo "gone")
echo "tqapi_running=$RUNNING tqapi_exitcode=$EXITCODE"
docker logs "$TQ_NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true

QCODE=000
if [[ "$RUNNING" == "true" ]]; then
    START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
    END=$(( $(date -u +%s) + 120 ))
    QCODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/d05-query.json" -w "%{http_code}" \
        "http://localhost:19104/api/v1/traces" \
        --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}" 2>/dev/null || echo "000")
fi
echo "query_code=$QCODE"
[[ -f "'"$EVIDENCE_DIR"'/d05-query.json" ]] && echo "query_count=$(jq length "'"$EVIDENCE_DIR"'/d05-query.json" 2>/dev/null || echo NA)"
docker stop --time 3 "$TQ_NAME" >/dev/null 2>&1 || true
docker rm "$TQ_NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" D05 "$INLINE"

OUT="$EVIDENCE_DIR/D05.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
RUNNING=$(val tqapi_running); EXITCODE=$(val tqapi_exitcode); QCODE=$(val query_code)

if [[ "$RUNNING" == "true" ]]; then
    [[ "$QCODE" == "200" ]] || { echo "service up but query returned $QCODE" >&2; exit 1; }
    CNT=$(jq 'length' "$EVIDENCE_DIR/d05-query.json")
    [[ "$CNT" -ge 1 ]] || { echo "recovery branch but 0 spans recovered" >&2; cat "$EVIDENCE_DIR/d05-query.json" >&2; exit 1; }
    WRONG=$(jq --arg s "d05-pilot" '[.[] | select((.resource_attributes."service.name") != $s)] | length' "$EVIDENCE_DIR/d05-query.json")
    [[ "$WRONG" == "0" ]] || { echo "recovered $WRONG spans with wrong service (possible corrupt/torn record)" >&2; exit 1; }
    echo "OK — ray torn WAL tail tolerated: trace-query-api recovered ${CNT} intact span(s) (all service=d05-pilot) and ignored the torn trailing line (graceful recovery, the shared wal_recovery seam on the Ray store)"
else
    [[ "$EXITCODE" != "0" && "$EXITCODE" != "gone" ]] || { echo "not running but exit code '$EXITCODE'" >&2; exit 1; }
    grep -qE 'PersistenceFailed|WAL parse error' "$EVIDENCE_DIR/trace-query-api.stderr.txt" \
        || { echo "fail-closed but no clear PersistenceFailed/WAL-parse error" >&2; cat "$EVIDENCE_DIR/trace-query-api.stderr.txt" >&2; exit 1; }
    echo "OK — ray torn WAL tail does NOT yield corrupt data: trace-query-api fails closed (exit ${EXITCODE}) with a clear error, serves nothing (SAFE; note: ray was expected to RECOVER at this SHA — investigate if seen)"
fi
