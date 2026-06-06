#!/usr/bin/env bash
# TQ06 — the /by_id arm matches a trace_id case-insensitively: an
# UPPERCASE 32-hex id resolves the same trace stored under its canonical
# lowercase id. Covers UC-TRC-005. Spans round-trip gateway -> Ray ->
# trace-query-api; the canonical id is discovered from the window arm,
# upper-cased, and looked up by-id.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SERVICE="tq06-pilot"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="tq06-gw-$$"; TQ_NAME="tq06-tqapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14332:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    traces --otlp-endpoint localhost:14332 --otlp-insecure --otlp-http \
    --traces 5 --child-spans 1 --service "$SERVICE" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$TQ_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme -e RUST_LOG=info -p 19123:9092 "$TQAPI_IMAGE" > /dev/null
sleep 3
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
WURL="http://localhost:19123/api/v1/traces"; BURL="http://localhost:19123/api/v1/traces/by_id"

curl -sS -G -o "'"$EVIDENCE_DIR"'/window.json" "$WURL" \
    --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}" >/dev/null
TID=$(jq -r ".[0].trace_id // empty" "'"$EVIDENCE_DIR"'/window.json")
TID_UPPER=$(printf "%s" "$TID" | tr "a-f" "A-F")
echo "canonical_lower=${TID}"
echo "queried_upper=${TID_UPPER}"
LOWER_CODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/byid-lower.json" -w "%{http_code}" "$BURL" --data-urlencode "trace_id=${TID}")
UPPER_CODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/byid-upper.json" -w "%{http_code}" "$BURL" --data-urlencode "trace_id=${TID_UPPER}")
echo "lower_code=${LOWER_CODE}"
echo "upper_code=${UPPER_CODE}"
echo "lower_spans=$(jq length "'"$EVIDENCE_DIR"'/byid-lower.json")"
echo "upper_spans=$(jq length "'"$EVIDENCE_DIR"'/byid-upper.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" TQ06 "$INLINE"

OUT="$EVIDENCE_DIR/TQ06.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
TID=$(val canonical_lower)
[[ -n "$TID" && "$TID" != "empty" ]] || { echo "no trace_id discovered" >&2; exit 1; }
[[ "$(val canonical_lower)" =~ ^[0-9a-f]{32}$ ]] || { echo "canonical id is not lowercase 32-hex: $(val canonical_lower)" >&2; exit 1; }
[[ "$(val upper_code)" == "200" ]] || { echo "uppercase by-id expected 200, got $(val upper_code)" >&2; exit 1; }
LS=$(val lower_spans); US=$(val upper_spans)
[[ "$US" -ge 1 ]] || { echo "uppercase by-id returned no spans (case-insensitive match failed)" >&2; exit 1; }
[[ "$US" == "$LS" ]] || { echo "uppercase by-id span count ($US) != lowercase ($LS)" >&2; exit 1; }
echo "OK — an uppercase 32-hex trace_id resolves the same trace as its lowercase canonical id (${US} spans both ways)"
