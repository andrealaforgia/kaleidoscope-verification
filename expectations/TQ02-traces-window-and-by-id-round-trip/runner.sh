#!/usr/bin/env bash
# TQ02 — a span emitted with a known service round-trips through the
# kaleidoscope-gateway into the durable Ray store and is then
# readable through BOTH of trace-query-api's arms:
#   - the window arm  GET /api/v1/traces?service=&start=&end=
#     returns the ingested spans, filtered by service (a bogus
#     service returns []);
#   - the by-id arm   GET /api/v1/traces/by_id?trace_id=<32-hex>
#     resolves a trace_id discovered from the window response and
#     returns every span sharing it.
# This proves the read arms actually return ingested data (TQ01 only
# proved the by-id parser). Crosses gateway -> Ray -> trace-query-api.
# Anchors ADR-0048 (window arm) + ADR-0053 (by-id) at the surface.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SERVICE="tq02-pilot"
ABSENT="tq02-absent-service"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="tq02-gw-$$"
TQ_NAME="tq02-tqapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14322:4318 \
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

# Emit 5 traces (root + child each) tagged with the known service.
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    traces \
    --otlp-endpoint localhost:14322 --otlp-insecure --otlp-http \
    --traces 5 --child-spans 1 \
    --service "$SERVICE" \
    > /tmp/tg6.out 2> /tmp/tg6.err || { echo "telemetrygen traces failed" >&2; cat /tmp/tg6.err >&2; exit 1; }
cp /tmp/tg6.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"

docker stop --time 10 "$GW_NAME" > /dev/null
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d \
    --name "$TQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19096:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
WURL="http://localhost:19096/api/v1/traces"
BURL="http://localhost:19096/api/v1/traces/by_id"

# Window arm: matching service.
WCODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq02-window.json" -w "%{http_code}" \
    "$WURL" --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}")
echo "window_code=${WCODE}"
# Window arm: bogus service (control).
ACODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq02-window-absent.json" -w "%{http_code}" \
    "$WURL" --data-urlencode "service=${ABSENT}" --data-urlencode "start=${START}" --data-urlencode "end=${END}")
echo "absent_code=${ACODE}"

# Discover a trace_id from the window response and look it up by-id.
TID=$(jq -r ".[0].trace_id // empty" "'"$EVIDENCE_DIR"'/tq02-window.json")
echo "discovered_trace_id=${TID}"
BCODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq02-byid.json" -w "%{http_code}" \
    "$BURL" --data-urlencode "trace_id=${TID}")
echo "byid_code=${BCODE}"

docker logs "$TQ_NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true
echo "window=$(jq length "'"$EVIDENCE_DIR"'/tq02-window.json") absent=$(jq length "'"$EVIDENCE_DIR"'/tq02-window-absent.json") byid=$(jq length "'"$EVIDENCE_DIR"'/tq02-byid.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" TQ02 "$INLINE"

OUT="$EVIDENCE_DIR/TQ02.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
WIN="$EVIDENCE_DIR/tq02-window.json"
ABS="$EVIDENCE_DIR/tq02-window-absent.json"
BID="$EVIDENCE_DIR/tq02-byid.json"

[[ "$(val window_code)" == "200" ]] || { echo "window arm expected 200, got $(val window_code)" >&2; exit 1; }
[[ "$(val absent_code)" == "200" ]] || { echo "absent-service expected 200, got $(val absent_code)" >&2; exit 1; }
[[ "$(val byid_code)"  == "200" ]] || { echo "by-id arm expected 200, got $(val byid_code)" >&2; exit 1; }

# Window arm: matching service returns >=1 span, every span carries the service.
WCOUNT=$(jq 'length' "$WIN")
[[ "$WCOUNT" -ge 1 ]] || { echo "window arm returned no spans; traces did not round-trip" >&2; cat "$WIN" >&2; exit 1; }
WRONG_SVC=$(jq --arg s "tq02-pilot" '[.[] | select((.resource_attributes."service.name") != $s)] | length' "$WIN")
[[ "$WRONG_SVC" == "0" ]] || { echo "window arm returned $WRONG_SVC spans with the wrong service.name" >&2; cat "$WIN" >&2; exit 1; }

# Control: a bogus service returns the empty array (the filter filters).
ACOUNT=$(jq 'length' "$ABS")
[[ "$ACOUNT" == "0" ]] || { echo "bogus service expected [], got $ACOUNT spans" >&2; exit 1; }

# By-id arm: the discovered trace_id resolves to >=1 span, ALL sharing it.
TID=$(val discovered_trace_id)
[[ -n "$TID" && "$TID" != "empty" ]] || { echo "no trace_id discovered from the window response" >&2; exit 1; }
BCOUNT=$(jq 'length' "$BID")
[[ "$BCOUNT" -ge 1 ]] || { echo "by-id returned no spans for trace_id $TID" >&2; cat "$BID" >&2; exit 1; }
OTHER_TID=$(jq --arg t "$TID" '[.[] | select(.trace_id != $t)] | length' "$BID")
[[ "$OTHER_TID" == "0" ]] || { echo "by-id returned $OTHER_TID spans NOT sharing trace_id $TID" >&2; cat "$BID" >&2; exit 1; }

echo "OK — traces round-trip gateway->Ray->trace-query-api: window arm returns ${WCOUNT} spans all carrying service=tq02-pilot (bogus service -> []); by-id arm resolves discovered trace_id ${TID} to ${BCOUNT} spans, all sharing it"
