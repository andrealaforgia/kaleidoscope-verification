#!/usr/bin/env bash
# Q10 — query-api honours the full PromQL label-matcher set over two
# series of the same metric `gen` differing by labels (job=x/env=prod and
# job=y/env=dev). Covers UC-MET-003 (inequality !=), UC-MET-004 (regex
# =~), UC-MET-005 (negated regex !~), UC-MET-006 (multiple matchers AND).
# Metric labels come from telemetrygen --telemetry-attributes (OTLP data
# point attributes -> Prometheus labels). Round-trip gateway -> Pulse ->
# query-api.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="q10-gw-$$"; QN="q10-qapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$QN" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$QN" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14342:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
docker run --rm --network host "$TG" metrics --otlp-endpoint localhost:14342 --otlp-insecure --otlp-http \
    --duration 1s --rate 2 --telemetry-attributes job=\"x\" --telemetry-attributes env=\"prod\" >/dev/null 2>&1
docker run --rm --network host "$TG" metrics --otlp-endpoint localhost:14342 --otlp-insecure --otlp-http \
    --duration 1s --rate 2 --telemetry-attributes job=\"y\" --telemetry-attributes env=\"dev\" >/dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$QN" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info -p 19142:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
U="http://localhost:19142/api/v1/query_range"
# Write each query result to its own JSON; parsing happens outside the
# INLINE to avoid nested-quote capture fragility.
run_q() { curl -sS -G -o "'"$EVIDENCE_DIR"'/q-$1.json" "$U" \
    --data-urlencode "query=$2" --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode step=15s; }
run_q neq        "gen{job!=\"x\"}"
run_q regex      "gen{job=~\"x.*\"}"
run_q negregex   "gen{job!~\"x.*\"}"
run_q and_match  "gen{job=\"x\",env=\"prod\"}"
run_q and_nomatch "gen{job=\"x\",env=\"dev\"}"
echo "queries written"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" Q10 "$INLINE"

jobs() { jq -r '[.data.result[].metric.job]|sort|unique|join(",")' "$EVIDENCE_DIR/q-$1.json"; }
len()  { jq -r '.data.result|length' "$EVIDENCE_DIR/q-$1.json"; }

[[ "$(jobs neq)"       == "y" ]] || { echo "FAIL: job!=\"x\" expected [y], got [$(jobs neq)]" >&2; exit 1; }
[[ "$(jobs regex)"     == "x" ]] || { echo "FAIL: job=~\"x.*\" expected [x], got [$(jobs regex)]" >&2; exit 1; }
[[ "$(jobs negregex)"  == "y" ]] || { echo "FAIL: job!~\"x.*\" expected [y], got [$(jobs negregex)]" >&2; exit 1; }
[[ "$(jobs and_match)" == "x" ]] || { echo "FAIL: job=\"x\",env=\"prod\" expected [x], got [$(jobs and_match)]" >&2; exit 1; }
[[ "$(len and_nomatch)" == "0" ]] || { echo "FAIL: job=\"x\",env=\"dev\" expected empty, got $(len and_nomatch)" >&2; exit 1; }
echo "OK — !=, =~, !~ each select the right series; multiple matchers AND together (job=x,env=prod matches; job=x,env=dev is empty)"
