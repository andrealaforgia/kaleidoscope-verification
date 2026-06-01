#!/usr/bin/env bash
# LQ07 — cross-tenant read isolation: logs ingested under one tenant are
# NOT readable by a different tenant through log-query-api, even on the
# same durable store. A multi-tenant observability platform that leaks
# across tenants is broken; this pins the isolation invariant at the
# running read surface.
#
# Scenario:
#   1. gateway up with KALEIDOSCOPE_DEFAULT_TENANT=tenant-a; ingest logs
#      with a known body; SIGTERM to flush Lumen.
#   2. log-query-api on the SAME /data with TENANT=tenant-b queries the
#      body -> MUST be [] (tenant-b cannot see tenant-a's records).
#   3. log-query-api on the SAME /data with TENANT=tenant-a queries the
#      same body -> returns the records. This control proves the data IS
#      present and durable, so tenant-b's empty result is ISOLATION, not
#      merely missing data.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NEEDLE="lq07-secret-marker"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq07-gw-$$"
LQB_NAME="lq07-lqb-$$"
LQA_NAME="lq07-lqa-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$LQB_NAME" "$LQA_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$LQB_NAME" "$LQA_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Ingest under tenant-a.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=tenant-a -e RUST_LOG=info \
    -p 14328:4318 \
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
    logs --otlp-endpoint localhost:14328 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 --body "$NEEDLE" \
    --otlp-attributes service.name=\"lq07-pilot\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null
docker rm "$GW_NAME" >/dev/null 2>&1 || true

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))

# 2. Read as tenant-b -> must be empty.
docker run --rm -d \
    --name "$LQB_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-b -e RUST_LOG=info \
    -p 19103:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3
CODE_B=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/lq07-tenant-b.json" -w "%{http_code}" \
    "http://localhost:19103/api/v1/logs" \
    --data-urlencode "start=${START}" --data-urlencode "end=${END}" \
    --data-urlencode "body_contains=${NEEDLE}")
echo "code_b=${CODE_B}"
docker stop --time 5 "$LQB_NAME" >/dev/null 2>&1 || true
docker rm "$LQB_NAME" >/dev/null 2>&1 || true

# 3. Read as tenant-a -> control, must have the data.
docker run --rm -d \
    --name "$LQA_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-a -e RUST_LOG=info \
    -p 19103:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3
CODE_A=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/lq07-tenant-a.json" -w "%{http_code}" \
    "http://localhost:19103/api/v1/logs" \
    --data-urlencode "start=${START}" --data-urlencode "end=${END}" \
    --data-urlencode "body_contains=${NEEDLE}")
echo "code_a=${CODE_A}"
docker stop --time 5 "$LQA_NAME" >/dev/null 2>&1 || true
docker rm "$LQA_NAME" >/dev/null 2>&1 || true

echo "tenant_b_count=$(jq length "'"$EVIDENCE_DIR"'/lq07-tenant-b.json")"
echo "tenant_a_count=$(jq length "'"$EVIDENCE_DIR"'/lq07-tenant-a.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ07 "$INLINE"

OUT="$EVIDENCE_DIR/LQ07.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val code_b)" == "200" ]] || { echo "tenant-b query expected 200, got $(val code_b)" >&2; exit 1; }
[[ "$(val code_a)" == "200" ]] || { echo "tenant-a query expected 200, got $(val code_a)" >&2; exit 1; }

B=$(val tenant_b_count)
A=$(val tenant_a_count)
# Isolation: tenant-b sees NOTHING of tenant-a's data.
[[ "$B" == "0" ]] || { echo "TENANT LEAK: tenant-b read $B of tenant-a's records" >&2; cat "$EVIDENCE_DIR/lq07-tenant-b.json" >&2; exit 1; }
# Control: the data IS present under tenant-a (so B's empty is isolation, not absence).
[[ "$A" -ge 1 ]] || { echo "control failed: tenant-a sees $A records; cannot distinguish isolation from missing data" >&2; exit 1; }

echo "OK — cross-tenant read isolation: logs ingested under tenant-a are invisible to tenant-b (0 records) while tenant-a reads them (${A} records); the empty result for tenant-b is isolation, not absence"
