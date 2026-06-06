#!/usr/bin/env bash
# LQ10 — a log exported through the gateway preserves its OTLP resource
# attributes and its trace/span correlation IDs all the way into Lumen,
# readable via log-query-api. Covers UC-GWLOG-003 (resource attributes
# mapped: service.name) and UC-GWLOG-005 (trace_id/span_id preserved,
# enabling trace<->log join). Round-trip gateway -> Lumen -> log-query-api.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

TRACE_HEX="deadbeefdeadbeefdeadbeefdeadbeef"
SPAN_HEX="cafef00dcafef00d"

INLINE='
NEEDLE="lq10-correlated"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq10-gw-$$"; LQ_NAME="lq10-lq-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14361:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    logs --otlp-endpoint localhost:14361 --otlp-insecure --otlp-http \
    --duration 1s --rate 3 --body "$NEEDLE" --severity-number 17 --severity-text Error \
    --trace-id deadbeefdeadbeefdeadbeefdeadbeef --span-id cafef00dcafef00d \
    --otlp-attributes service.name=\"lq10-svc\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$LQ_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -e RUST_LOG=info -p 19161:9091 "$LQAPI_IMAGE" > /dev/null
sleep 3
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
curl -sS -G -o "'"$EVIDENCE_DIR"'/logs.json" "http://localhost:19161/api/v1/logs" \
    --data-urlencode "start=${START}" --data-urlencode "end=${END}" --data-urlencode "body_contains=${NEEDLE}" >/dev/null
echo "count=$(jq length "'"$EVIDENCE_DIR"'/logs.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ10 "$INLINE"

J="$EVIDENCE_DIR/logs.json"
[[ "$(jq length "$J")" -ge 1 ]] || { echo "no correlated log round-tripped through the gateway" >&2; exit 1; }
# UC-GWLOG-003: service.name preserved in resource_attributes.
SVC=$(jq -r '.[0].resource_attributes."service.name"' "$J")
[[ "$SVC" == "lq10-svc" ]] || { echo "resource attribute service.name not preserved (got $SVC)" >&2; exit 1; }
# UC-GWLOG-005: trace_id / span_id preserved (byte arrays -> hex).
TID=$(jq -r '.[0].trace_id[]' "$J" | awk '{printf "%02x",$1}')
SID=$(jq -r '.[0].span_id[]'  "$J" | awk '{printf "%02x",$1}')
[[ "$TID" == "$TRACE_HEX" ]] || { echo "trace_id not preserved (got $TID, expected $TRACE_HEX)" >&2; exit 1; }
[[ "$SID" == "$SPAN_HEX" ]]  || { echo "span_id not preserved (got $SID, expected $SPAN_HEX)" >&2; exit 1; }
echo "OK — gateway preserves resource service.name (lq10-svc) and the trace_id/span_id correlation IDs ($TRACE_HEX / $SPAN_HEX) into Lumen, readable via log-query-api"
