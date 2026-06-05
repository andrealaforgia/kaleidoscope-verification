#!/usr/bin/env bash
# EG02 — End-to-end via kaleidoscope-gateway over OTLP/gRPC. The gRPC
# counterpart to EG01 (which uses OTLP/HTTP): a metric exported to the
# gateway's gRPC receiver (:4317) is persisted to Pulse and read back
# through query-api. Pins that the gateway's gRPC ingest path works end
# to end, not just the HTTP one.
#
# Given the gateway is running and a metric is exported over OTLP/gRPC
# When the gateway is stopped (Pulse flushes) and query-api reopens /data
# Then query_range returns the metric (status=success, __name__=gen).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared; mkdir -p "$SHARED_DATA"
GW_NAME="eg02-gw-$$"; QAPI_NAME="eg02-qapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 1. Start gateway, map the gRPC port (4317) on a unique high host port.
docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14335:4317 "$GW_IMAGE" > /dev/null
SAW=""; for _ in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2

# 2. Export one metric over OTLP/gRPC (NO --otlp-http -> gRPC transport).
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14335 --otlp-insecure \
    --duration 1s --rate 1 --otlp-attributes service.name=\"eg02-pilot\" \
    > /tmp/tg.out 2> /tmp/tg.err || { echo "telemetrygen (gRPC) failed" >&2; cat /tmp/tg.err >&2; exit 1; }
cp /tmp/tg.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"

# 3. Stop gateway (Pulse flushes).
docker stop --time 10 "$GW_NAME" > /dev/null
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# 4. query-api on the same /data.
docker run --rm -d --name "$QAPI_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19102:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(date -u +%s)
curl -sS "http://localhost:19102/api/v1/query_range?query=gen&start=${START}&end=${END}&step=15s" \
    > "'"$EVIDENCE_DIR"'/query-response.json"
docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
echo "---response head---"; head -c 400 "'"$EVIDENCE_DIR"'/query-response.json"; echo
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG02 "$INLINE"

R="$EVIDENCE_DIR/query-response.json"
STATUS=$(jq -r '.status' "$R" 2>/dev/null)
[[ "$STATUS" == "success" ]] || { echo "FAIL: expected status=success, got: $STATUS" >&2; cat "$R" >&2; exit 1; }
N=$(jq -r '.data.result | length' "$R")
[[ "$N" -gt 0 ]] || { echo "FAIL: empty result; gRPC-ingested metric not readable via query-api" >&2; cat "$R" >&2; exit 1; }
NAME=$(jq -r '.data.result[0].metric.__name__' "$R")
[[ "$NAME" == "gen" ]] || { echo "FAIL: expected __name__=gen, got: $NAME" >&2; exit 1; }
echo "OK — OTLP/gRPC metric ingested via the gateway is readable via query-api (status=success, __name__=gen, ${N} series). The gateway's gRPC receiver persists to Pulse end to end, matching the HTTP path (EG01)."
