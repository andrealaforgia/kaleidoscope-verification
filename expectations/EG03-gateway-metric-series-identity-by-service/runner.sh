#!/usr/bin/env bash
# EG03 — two services emitting the same metric `gen` are kept as two
# DISTINCT series (series identity by resource service.name). Covers
# UC-GWMET-003. Round-trip gateway -> Pulse -> query-api.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="eg03-gw-$$"; QN="eg03-qapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$QN" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$QN" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14372:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
docker run --rm --network host "$TG" metrics --otlp-endpoint localhost:14372 --otlp-insecure --otlp-http \
    --duration 1s --rate 2 --otlp-attributes service.name=\"svc-a\" >/dev/null 2>&1
docker run --rm --network host "$TG" metrics --otlp-endpoint localhost:14372 --otlp-insecure --otlp-http \
    --duration 1s --rate 2 --otlp-attributes service.name=\"svc-b\" >/dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$QN" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info -p 19172:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
curl -sS -G -o "'"$EVIDENCE_DIR"'/gen.json" "http://localhost:19172/api/v1/query_range" \
    --data-urlencode query=gen --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode step=15s >/dev/null
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG03 "$INLINE"

J="$EVIDENCE_DIR/gen.json"
[[ "$(jq -r .status "$J")" == "success" ]] || { echo "query not success" >&2; exit 1; }
NSERIES=$(jq -r '.data.result | length' "$J")
[[ "$NSERIES" -eq 2 ]] || { echo "expected 2 distinct series, got $NSERIES" >&2; jq -c '.data.result[].metric' "$J" >&2; exit 1; }
SVCS=$(jq -r '[.data.result[].metric."service.name"] | sort | join(",")' "$J")
[[ "$SVCS" == "svc-a,svc-b" ]] || { echo "two services not kept distinct (service.name labels: $SVCS)" >&2; exit 1; }
echo "OK — two services on metric gen are kept as two distinct series, identified by service.name (svc-a, svc-b)"
