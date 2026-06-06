#!/usr/bin/env bash
# TQ07 — a span exported through the gateway preserves its attributes and
# its start/end timing into Ray, readable via trace-query-api. Covers
# UC-GWTRC-005 (span attributes & timing survive). Round-trip
# gateway -> Ray -> trace-query-api. (telemetrygen stamps fixed span
# attributes net.peer.ip=1.2.3.4 and peer.service=telemetrygen-client.)
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SERVICE="tq07-pilot"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="tq07-gw-$$"; TQ_NAME="tq07-tqapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14373:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    traces --otlp-endpoint localhost:14373 --otlp-insecure --otlp-http \
    --traces 3 --child-spans 1 --service "$SERVICE" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$TQ_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme -e RUST_LOG=info -p 19173:9092 "$TQAPI_IMAGE" > /dev/null
sleep 3
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
curl -sS -G -o "'"$EVIDENCE_DIR"'/spans.json" "http://localhost:19173/api/v1/traces" \
    --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}" >/dev/null
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" TQ07 "$INLINE"

J="$EVIDENCE_DIR/spans.json"
[[ "$(jq length "$J")" -ge 1 ]] || { echo "no spans round-tripped" >&2; exit 1; }
# A span carries a name.
NAME=$(jq -r '.[0].name' "$J")
[[ -n "$NAME" && "$NAME" != "null" ]] || { echo "span name not preserved" >&2; exit 1; }
# Timing: start < end, both non-zero (duration preserved).
ST=$(jq -r '.[0].start_time_unix_nano' "$J"); EN=$(jq -r '.[0].end_time_unix_nano' "$J")
[[ "$ST" =~ ^[0-9]+$ && "$EN" =~ ^[0-9]+$ && "$ST" -gt 0 && "$EN" -gt "$ST" ]] \
    || { echo "span timing not preserved (start=$ST end=$EN)" >&2; exit 1; }
# Attributes: telemetrygen's fixed span attributes survive.
PEER=$(jq -r '.[] | select(.attributes."peer.service"=="telemetrygen-client") | .attributes."peer.service"' "$J" | head -1)
[[ "$PEER" == "telemetrygen-client" ]] || { echo "span attribute peer.service not preserved" >&2; jq -c '.[0].attributes' "$J" >&2; exit 1; }
IP=$(jq -r '.[0].attributes."net.peer.ip"' "$J")
[[ "$IP" == "1.2.3.4" ]] || { echo "span attribute net.peer.ip not preserved (got $IP)" >&2; exit 1; }
echo "OK — span name, start/end timing (end>start>0), and attributes (peer.service, net.peer.ip) all survive gateway -> Ray -> trace-query-api"
