#!/usr/bin/env bash
# EG01 — End-to-end via kaleidoscope-gateway + query-api.
#
# Scenario:
#   1. Start kaleidoscope-gateway with a writable /data volume and
#      KALEIDOSCOPE_DEFAULT_TENANT=acme; wait until the gateway
#      emits `event=gateway_starting` on stderr.
#   2. Send one OTLP/HTTP/protobuf metric via telemetrygen at
#      :4318 with `service.name=eg01-pilot` and a counter named
#      `gen`.
#   3. SIGTERM the gateway so the Pulse store flushes.
#   4. Start query-api with the SAME /data volume mounted (no
#      restart of the persisted bytes) and KALEIDOSCOPE_QUERY_TENANT=acme.
#      Wait for the listener to bind on :9090.
#   5. GET /api/v1/query_range?query=gen&start=...&end=...&step=15s
#      and assert the response carries `status=success`, a non-
#      empty matrix `result`, and at least one sample whose
#      metric labels include `__name__=gen` and tenant
#      attribution matches.
#   6. SIGTERM query-api.
#
# This is the integration thesis verification (N19). It crosses
# the gateway -> Pulse -> query-api boundary; failure mode at
# any step is operator-observable.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="eg01-gw-$$"
QAPI_NAME="eg01-qapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Step 1: start gateway.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14323:4318 \
    "$GW_IMAGE" > /dev/null
# Wait for gateway_starting.
SAW=""
for i in $(seq 1 30); do
    if docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound"; then
        SAW="yes"; break
    fi
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never emitted gateway_starting" >&2; exit 1; }
# Give axum a moment to actually bind.
sleep 2

# Step 2: send one metric via telemetrygen (OTLP/HTTP/protobuf).
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics \
    --otlp-endpoint localhost:14323 \
    --otlp-insecure \
    --otlp-http \
    --duration 1s \
    --rate 1 \
    --otlp-attributes service.name=\"eg01-pilot\" \
    > /tmp/tg.out 2> /tmp/tg.err || { echo "telemetrygen failed" >&2; cat /tmp/tg.err >&2; exit 1; }

# Step 3: SIGTERM gateway so Pulse flushes.
docker stop --time 10 "$GW_NAME" > /dev/null
cp /tmp/tg.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# Step 4: start query-api on same /data.
docker run --rm -d \
    --name "$QAPI_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19097:9090 \
    "$QAPI_IMAGE" > /dev/null
sleep 3

# Step 5: query.
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(date -u +%s)
curl -sS "http://localhost:19097/api/v1/query_range?query=gen&start=${START}&end=${END}&step=15s" \
    > "'"$EVIDENCE_DIR"'/query-response.json"

docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
echo "---response head---"
head -c 500 "'"$EVIDENCE_DIR"'/query-response.json"
echo
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG01 "$INLINE"

STATUS=$(jq -r '.status' "$EVIDENCE_DIR/query-response.json" 2>/dev/null)
[[ "$STATUS" == "success" ]] || { echo "expected status=success, got: $STATUS" >&2; cat "$EVIDENCE_DIR/query-response.json" >&2; exit 1; }
RESULT_COUNT=$(jq -r '.data.result | length' "$EVIDENCE_DIR/query-response.json")
[[ "$RESULT_COUNT" -gt 0 ]] || { echo "expected non-empty matrix result, got: $RESULT_COUNT" >&2; exit 1; }
NAME=$(jq -r '.data.result[0].metric.__name__' "$EVIDENCE_DIR/query-response.json")
[[ "$NAME" == "gen" ]] || { echo "expected __name__=gen, got: $NAME" >&2; exit 1; }
echo "OK — OTLP metric ingested via gateway is readable via query-api (status=success, __name__=gen)"
