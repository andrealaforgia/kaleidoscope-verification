#!/usr/bin/env bash
# Q08 — cross-tenant read isolation for METRICS (the query-api analogue
# of LQ07). A metric ingested through the gateway under tenant-a is NOT
# visible to a query-api instance bound to tenant-b, even on the same
# durable Pulse store. UC-TEN-002 (metrics isolated by tenant); also
# demonstrates UC-TEN-006 (one-tenant-per-instance binding via the
# KALEIDOSCOPE_QUERY_TENANT env var, no query param can widen scope).
#
# Scenario (mirrors LQ07):
#   1. gateway KALEIDOSCOPE_DEFAULT_TENANT=tenant-a; telemetrygen one
#      `gen` metric; SIGTERM to flush Pulse.
#   2. query-api on the SAME /data with TENANT=tenant-b queries gen ->
#      status=success with an EMPTY matrix (no leak).
#   3. query-api on the SAME /data with TENANT=tenant-a queries gen ->
#      non-empty matrix (control: the data IS present, so tenant-b's
#      empty result is isolation, not absence).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="q08-gw-$$"
QB_NAME="q08-qb-$$"
QA_NAME="q08-qa-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$QB_NAME" "$QA_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$QB_NAME" "$QA_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Ingest a metric under tenant-a.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=tenant-a -e RUST_LOG=info \
    -p 14329:4318 \
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
    metrics --otlp-endpoint localhost:14329 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 --otlp-attributes service.name=\"q08-pilot\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null
docker rm "$GW_NAME" >/dev/null 2>&1 || true

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
Q="query=gen&start=${START}&end=${END}&step=15s"

# 2. Read as tenant-b -> must be empty.
docker run --rm -d \
    --name "$QB_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=tenant-b -e RUST_LOG=info \
    -p 19104:9090 \
    "$QAPI_IMAGE" > /dev/null
sleep 3
curl -sS -o "'"$EVIDENCE_DIR"'/q08-tenant-b.json" "http://localhost:19104/api/v1/query_range?${Q}"
docker stop --time 5 "$QB_NAME" >/dev/null 2>&1 || true
docker rm "$QB_NAME" >/dev/null 2>&1 || true

# 3. Read as tenant-a -> control, must have the data.
docker run --rm -d \
    --name "$QA_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=tenant-a -e RUST_LOG=info \
    -p 19104:9090 \
    "$QAPI_IMAGE" > /dev/null
sleep 3
curl -sS -o "'"$EVIDENCE_DIR"'/q08-tenant-a.json" "http://localhost:19104/api/v1/query_range?${Q}"
docker stop --time 5 "$QA_NAME" >/dev/null 2>&1 || true
docker rm "$QA_NAME" >/dev/null 2>&1 || true

echo "status_b=$(jq -r .status "'"$EVIDENCE_DIR"'/q08-tenant-b.json")"
echo "count_b=$(jq -r ".data.result | length" "'"$EVIDENCE_DIR"'/q08-tenant-b.json")"
echo "status_a=$(jq -r .status "'"$EVIDENCE_DIR"'/q08-tenant-a.json")"
echo "count_a=$(jq -r ".data.result | length" "'"$EVIDENCE_DIR"'/q08-tenant-a.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" Q08 "$INLINE"

OUT="$EVIDENCE_DIR/Q08.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val status_b)" == "success" ]] || { echo "tenant-b query not success: $(val status_b)" >&2; exit 1; }
[[ "$(val status_a)" == "success" ]] || { echo "tenant-a query not success: $(val status_a)" >&2; exit 1; }
[[ "$(val count_b)" == "0" ]] || { echo "TENANT LEAK: tenant-b saw $(val count_b) metric series of tenant-a's data" >&2; cat "$EVIDENCE_DIR/q08-tenant-b.json" >&2; exit 1; }
[[ "$(val count_a)" -ge 1 ]] || { echo "control failed: tenant-a saw $(val count_a) series; cannot distinguish isolation from absence" >&2; exit 1; }
echo "OK — metric ingested under tenant-a is invisible to tenant-b (0 series) while tenant-a reads it ($(val count_a)); empty is isolation, not absence"
