#!/usr/bin/env bash
# EG05 — a single gateway ingesting one OTLP stream that carries all three
# signals (metrics + logs + traces) stores each into its own pillar, and
# each pillar is INDEPENDENTLY queryable via its own read API: metric via
# query-api, log via log-query-api, trace via trace-query-api. Covers
# UC-LOOP-004 (three pillars from one stream). The integration thesis:
# no cross-pillar interference, all three readable from one populated
# data volume. Round-trip gateway -> {Pulse,Lumen,Ray} -> the 3 read APIs.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
LOGMARK="eg05-loopmarker"; SVC="eg05-svc"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW="eg05-gw-$$"
cleanup() { docker stop --time 5 "$GW" eg05-q eg05-lq eg05-tq >/dev/null 2>&1 || true; docker rm "$GW" eg05-q eg05-lq eg05-tq >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14400:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
# One stream, three signals, same gateway endpoint.
docker run --rm --network host "$TG" metrics --otlp-endpoint localhost:14400 --otlp-insecure --otlp-http --duration 1s --rate 2 >/dev/null 2>&1
docker run --rm --network host "$TG" logs    --otlp-endpoint localhost:14400 --otlp-insecure --otlp-http --duration 1s --rate 3 --body "$LOGMARK" >/dev/null 2>&1
docker run --rm --network host "$TG" traces  --otlp-endpoint localhost:14400 --otlp-insecure --otlp-http --traces 3 --child-spans 1 --service "$SVC" >/dev/null 2>&1
docker stop --time 10 "$GW" >/dev/null; docker rm "$GW" >/dev/null 2>&1 || true

S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))

# Pillar 1: metric via query-api.
docker run --rm -d --name eg05-q -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_QUERY_TENANT=acme -p 19400:9090 "$QAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/metric.json" "http://localhost:19400/api/v1/query_range" --data-urlencode query=gen --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode step=15s >/dev/null
docker stop --time 3 eg05-q >/dev/null 2>&1 || true; docker rm eg05-q >/dev/null 2>&1 || true

# Pillar 2: log via log-query-api.
docker run --rm -d --name eg05-lq -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -p 19401:9091 "$LQAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/log.json" "http://localhost:19401/api/v1/logs" --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode "body_contains=$LOGMARK" >/dev/null
docker stop --time 3 eg05-lq >/dev/null 2>&1 || true; docker rm eg05-lq >/dev/null 2>&1 || true

# Pillar 3: trace via trace-query-api.
docker run --rm -d --name eg05-tq -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme -p 19402:9092 "$TQAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/trace.json" "http://localhost:19402/api/v1/traces" --data-urlencode "service=$SVC" --data-urlencode "start=$S" --data-urlencode "end=$E" >/dev/null
docker stop --time 3 eg05-tq >/dev/null 2>&1 || true; docker rm eg05-tq >/dev/null 2>&1 || true

echo "metric_series=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/metric.json")"
echo "log_count=$(jq length "'"$EVIDENCE_DIR"'/log.json")"
echo "trace_spans=$(jq length "'"$EVIDENCE_DIR"'/trace.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG05 "$INLINE"

OUT="$EVIDENCE_DIR/EG05.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
[[ "$(val metric_series)" -ge 1 ]] || { echo "metric pillar not independently queryable (0 series)" >&2; exit 1; }
[[ "$(val log_count)"     -ge 1 ]] || { echo "log pillar not independently queryable (0 logs)" >&2; exit 1; }
[[ "$(val trace_spans)"   -ge 1 ]] || { echo "trace pillar not independently queryable (0 spans)" >&2; exit 1; }
echo "OK — one gateway ingesting metrics+logs+traces stores each into its own pillar; all three are independently queryable (metric=$(val metric_series) series, log=$(val log_count), trace=$(val trace_spans) spans)"
