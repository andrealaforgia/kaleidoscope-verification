#!/usr/bin/env bash
# TQ05 — cross-tenant read isolation for TRACES (the trace-query-api
# analogue of LQ07/Q08). Spans ingested through the gateway under
# tenant-a are NOT visible to a trace-query-api instance bound to
# tenant-b, on the same durable Ray store. UC-TEN-003 (traces isolated
# by tenant); also demonstrates UC-TEN-006 (per-instance tenant binding
# via KALEIDOSCOPE_TRACE_QUERY_TENANT).
#
# Scenario (mirrors LQ07):
#   1. gateway KALEIDOSCOPE_DEFAULT_TENANT=tenant-a; telemetrygen 5
#      traces for service tq05-pilot; SIGTERM to flush Ray.
#   2. trace-query-api on the SAME /data with TENANT=tenant-b queries
#      the window arm for that service -> [] (no leak).
#   3. trace-query-api on the SAME /data with TENANT=tenant-a queries
#      the same service -> spans present (control).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SERVICE="tq05-pilot"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="tq05-gw-$$"
TB_NAME="tq05-tb-$$"
TA_NAME="tq05-ta-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$TB_NAME" "$TA_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$TB_NAME" "$TA_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Ingest traces under tenant-a.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=tenant-a -e RUST_LOG=info \
    -p 14330:4318 \
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
    traces --otlp-endpoint localhost:14330 --otlp-insecure --otlp-http \
    --traces 5 --child-spans 1 --service "$SERVICE" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null
docker rm "$GW_NAME" >/dev/null 2>&1 || true

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))

# 2. Read as tenant-b -> must be empty.
docker run --rm -d \
    --name "$TB_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=tenant-b -e RUST_LOG=info \
    -p 19105:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 3
CODE_B=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq05-tenant-b.json" -w "%{http_code}" \
    "http://localhost:19105/api/v1/traces" \
    --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}")
echo "code_b=${CODE_B}"
docker stop --time 5 "$TB_NAME" >/dev/null 2>&1 || true
docker rm "$TB_NAME" >/dev/null 2>&1 || true

# 3. Read as tenant-a -> control, must have the data.
docker run --rm -d \
    --name "$TA_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=tenant-a -e RUST_LOG=info \
    -p 19105:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 3
CODE_A=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq05-tenant-a.json" -w "%{http_code}" \
    "http://localhost:19105/api/v1/traces" \
    --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}")
echo "code_a=${CODE_A}"
docker stop --time 5 "$TA_NAME" >/dev/null 2>&1 || true
docker rm "$TA_NAME" >/dev/null 2>&1 || true

echo "count_b=$(jq length "'"$EVIDENCE_DIR"'/tq05-tenant-b.json")"
echo "count_a=$(jq length "'"$EVIDENCE_DIR"'/tq05-tenant-a.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" TQ05 "$INLINE"

OUT="$EVIDENCE_DIR/TQ05.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val code_b)" == "200" ]] || { echo "tenant-b query expected 200, got $(val code_b)" >&2; exit 1; }
[[ "$(val code_a)" == "200" ]] || { echo "tenant-a query expected 200, got $(val code_a)" >&2; exit 1; }
[[ "$(val count_b)" == "0" ]] || { echo "TENANT LEAK: tenant-b saw $(val count_b) of tenant-a's spans" >&2; cat "$EVIDENCE_DIR/tq05-tenant-b.json" >&2; exit 1; }
[[ "$(val count_a)" -ge 1 ]] || { echo "control failed: tenant-a saw $(val count_a) spans; cannot distinguish isolation from absence" >&2; exit 1; }
echo "OK — spans ingested under tenant-a are invisible to tenant-b (0) while tenant-a reads them ($(val count_a)); empty is isolation, not absence"
