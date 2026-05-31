#!/usr/bin/env bash
# LQ05 — log-query-api's `min_severity` floor actually filters across
# the durable boundary: records below the floor are excluded, records
# at or above it are returned. Anchors ADR-0052 (min_severity) /
# log-query-severity-filter-v0 (feat e281fca, gap N23) at the running
# surface.
#
# OTel severity numbers (lumen::SeverityNumber, bare i32 on the wire):
#   INFO = 9, WARN = 13, ERROR = 17.
# Two batches round-trip gateway -> Lumen -> log-query-api:
#   batch INFO  (severity-number 9,  body lq05-info-*)
#   batch ERROR (severity-number 17, body lq05-error-*)
# Then:
#   no filter            -> BOTH bodies present (proves both ingested)
#   min_severity=WARN    -> only severity_number >= 13: every record
#                           >= 13, NO lq05-info body, >=1 lq05-error
#   min_severity=ERROR   -> every record severity_number >= 17
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INFO_BODY="lq05-info-marker"
ERROR_BODY="lq05-error-marker"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq05-gw-$$"
LQ_NAME="lq05-lqapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14321:4318 \
    "$GW_IMAGE" > /dev/null
SAW=""
for i in $(seq 1 30); do
    if docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound"; then
        SAW="yes"; break
    fi
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never emitted gateway_starting" >&2; exit 1; }
sleep 2

TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
# batch INFO
docker run --rm --network host "$TG" logs \
    --otlp-endpoint localhost:14321 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 \
    --severity-number 9 --severity-text Info --body "$INFO_BODY" \
    --otlp-attributes service.name=\"lq05-pilot\" \
    > /tmp/tg5i.out 2> /tmp/tg5i.err || { echo "telemetrygen INFO failed" >&2; cat /tmp/tg5i.err >&2; exit 1; }
# batch ERROR
docker run --rm --network host "$TG" logs \
    --otlp-endpoint localhost:14321 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 \
    --severity-number 17 --severity-text Error --body "$ERROR_BODY" \
    --otlp-attributes service.name=\"lq05-pilot\" \
    > /tmp/tg5e.out 2> /tmp/tg5e.err || { echo "telemetrygen ERROR failed" >&2; cat /tmp/tg5e.err >&2; exit 1; }
cp /tmp/tg5i.err "'"$EVIDENCE_DIR"'/telemetrygen.info.stderr.txt"
cp /tmp/tg5e.err "'"$EVIDENCE_DIR"'/telemetrygen.error.stderr.txt"

docker stop --time 10 "$GW_NAME" > /dev/null
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d \
    --name "$LQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19094:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
URL="http://localhost:19094/api/v1/logs"
q() { curl -sS -G "$URL" --data-urlencode "start=${START}" --data-urlencode "end=${END}" "$@"; }

q -o "'"$EVIDENCE_DIR"'/lq05-full.json"  -w "full_code=%{http_code}\n"
q -o "'"$EVIDENCE_DIR"'/lq05-warn.json"  -w "warn_code=%{http_code}\n"  --data-urlencode "min_severity=WARN"
q -o "'"$EVIDENCE_DIR"'/lq05-error.json" -w "error_code=%{http_code}\n" --data-urlencode "min_severity=ERROR"

docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
echo "info_body=$INFO_BODY error_body=$ERROR_BODY"
echo "full=$(jq length "'"$EVIDENCE_DIR"'/lq05-full.json") warn=$(jq length "'"$EVIDENCE_DIR"'/lq05-warn.json") error=$(jq length "'"$EVIDENCE_DIR"'/lq05-error.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ05 "$INLINE"

OUT="$EVIDENCE_DIR/LQ05.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
FULL="$EVIDENCE_DIR/lq05-full.json"
WARN="$EVIDENCE_DIR/lq05-warn.json"
ERR="$EVIDENCE_DIR/lq05-error.json"

[[ "$(code full_code)" == "200" ]] || { echo "full expected 200, got $(code full_code)" >&2; exit 1; }
[[ "$(code warn_code)" == "200" ]] || { echo "warn expected 200, got $(code warn_code)" >&2; exit 1; }
[[ "$(code error_code)" == "200" ]] || { echo "error expected 200, got $(code error_code)" >&2; exit 1; }

# Control: with no floor, BOTH severities are present (both ingested).
INFO_IN_FULL=$(jq '[.[] | select(.body=="lq05-info-marker")] | length' "$FULL")
ERROR_IN_FULL=$(jq '[.[] | select(.body=="lq05-error-marker")] | length' "$FULL")
[[ "$INFO_IN_FULL" -ge 1 ]] || { echo "no INFO records ingested; fixture broken" >&2; cat "$FULL" >&2; exit 1; }
[[ "$ERROR_IN_FULL" -ge 1 ]] || { echo "no ERROR records ingested; fixture broken" >&2; cat "$FULL" >&2; exit 1; }

# min_severity=WARN (13): every returned record >= 13, no INFO body,
# at least one ERROR body.
WARN_COUNT=$(jq 'length' "$WARN")
[[ "$WARN_COUNT" -ge 1 ]] || { echo "min_severity=WARN returned nothing; floor over-filtered" >&2; exit 1; }
BELOW_WARN=$(jq '[.[] | select(.severity_number < 13)] | length' "$WARN")
[[ "$BELOW_WARN" == "0" ]] || { echo "min_severity=WARN leaked $BELOW_WARN records below severity 13" >&2; cat "$WARN" >&2; exit 1; }
INFO_IN_WARN=$(jq '[.[] | select(.body=="lq05-info-marker")] | length' "$WARN")
[[ "$INFO_IN_WARN" == "0" ]] || { echo "min_severity=WARN leaked $INFO_IN_WARN INFO records" >&2; exit 1; }
ERROR_IN_WARN=$(jq '[.[] | select(.body=="lq05-error-marker")] | length' "$WARN")
[[ "$ERROR_IN_WARN" -ge 1 ]] || { echo "min_severity=WARN dropped the ERROR records it should keep" >&2; exit 1; }

# min_severity=ERROR (17): every returned record >= 17.
BELOW_ERROR=$(jq '[.[] | select(.severity_number < 17)] | length' "$ERR")
[[ "$BELOW_ERROR" == "0" ]] || { echo "min_severity=ERROR leaked $BELOW_ERROR records below severity 17" >&2; cat "$ERR" >&2; exit 1; }

echo "OK — min_severity floor filters across the durable boundary: no-filter keeps both INFO+ERROR; min_severity=WARN keeps only severity>=13 (ERROR present, INFO excluded); min_severity=ERROR keeps only severity>=17"
