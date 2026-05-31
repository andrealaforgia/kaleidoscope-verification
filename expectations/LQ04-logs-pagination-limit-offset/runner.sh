#!/usr/bin/env bash
# LQ04 — log-query-api paginates /api/v1/logs with `limit` and
# `offset` over the stable-ordered, post-filter result set, with
# the documented cap-then-slice order and the documented 400 on an
# invalid limit. New feature at HEAD (feat 47fc5ef, ADR-0057
# log-query-pagination-v0, "handler-side slice, cap before slice").
#
# Records round-trip gateway -> Lumen -> log-query-api (same fixture
# as LQ02/LQ03). Against the full ordered result the runner asserts:
#   - limit=3            -> exactly the first 3 records (head page)
#   - offset=3 & limit=3 -> exactly records [3,6) (next page,
#                           contiguous and disjoint from page 1)
#   - limit=0            -> 400 "invalid limit"
#   - offset past end    -> 200 [] (empty page, NOT an error)
# The observed_time_unix_nano of each record is the stable sort key
# and the per-record identity used to compare pages.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
BODY="lq04-page-body"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq04-gw-$$"
LQ_NAME="lq04-lqapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Step 1: gateway up (unique high host port; see N27).
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14320:4318 \
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

# Step 2: emit ~20 log records (rate 10 over 2s) so there are enough
# rows to paginate two full pages.
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    logs \
    --otlp-endpoint localhost:14320 \
    --otlp-insecure \
    --otlp-http \
    --duration 2s \
    --rate 10 \
    --body "$BODY" \
    --otlp-attributes service.name=\"lq04-pilot\" \
    > /tmp/tg4.out 2> /tmp/tg4.err || { echo "telemetrygen failed" >&2; cat /tmp/tg4.err >&2; exit 1; }
cp /tmp/tg4.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"

# Step 3: SIGTERM gateway so Lumen flushes.
docker stop --time 10 "$GW_NAME" > /dev/null
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# Step 4: log-query-api on the same /data.
docker run --rm -d \
    --name "$LQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19093:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
URL="http://localhost:19093/api/v1/logs"
q() { curl -sS -G "$URL" --data-urlencode "start=${START}" --data-urlencode "end=${END}" "$@"; }

# Full result (ground-truth order).
q -o "'"$EVIDENCE_DIR"'/lq04-full.json" -w "full_code=%{http_code}\n"
# Page 1: limit=3.
q -o "'"$EVIDENCE_DIR"'/lq04-p1.json" -w "p1_code=%{http_code}\n" --data-urlencode "limit=3"
# Page 2: offset=3 limit=3.
q -o "'"$EVIDENCE_DIR"'/lq04-p2.json" -w "p2_code=%{http_code}\n" --data-urlencode "offset=3" --data-urlencode "limit=3"
# Invalid limit=0.
q -o "'"$EVIDENCE_DIR"'/lq04-inv.json" -w "inv_code=%{http_code}\n" --data-urlencode "limit=0"
# Offset past end.
q -o "'"$EVIDENCE_DIR"'/lq04-past.json" -w "past_code=%{http_code}\n" --data-urlencode "offset=1000000" --data-urlencode "limit=3"

docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
echo "body=$BODY"
echo "---full count---"; jq length "'"$EVIDENCE_DIR"'/lq04-full.json"
echo "---inv body---"; cat "'"$EVIDENCE_DIR"'/lq04-inv.json"; echo
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ04 "$INLINE"

OUT="$EVIDENCE_DIR/LQ04.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
FULL="$EVIDENCE_DIR/lq04-full.json"
P1="$EVIDENCE_DIR/lq04-p1.json"
P2="$EVIDENCE_DIR/lq04-p2.json"
INV="$EVIDENCE_DIR/lq04-inv.json"
PAST="$EVIDENCE_DIR/lq04-past.json"

[[ "$(code full_code)" == "200" ]] || { echo "full query expected 200, got $(code full_code)" >&2; exit 1; }
[[ "$(code p1_code)" == "200" ]] || { echo "page1 expected 200, got $(code p1_code)" >&2; exit 1; }
[[ "$(code p2_code)" == "200" ]] || { echo "page2 expected 200, got $(code p2_code)" >&2; exit 1; }
[[ "$(code past_code)" == "200" ]] || { echo "offset-past-end expected 200, got $(code past_code)" >&2; exit 1; }

TOTAL=$(jq 'length' "$FULL")
[[ "$TOTAL" -ge 6 ]] || { echo "need >=6 records to paginate two pages, got $TOTAL" >&2; exit 1; }

# Page 1 must be exactly the first 3 nanos of the full ordered set.
EXP_P1=$(jq -c '[.[].observed_time_unix_nano][0:3]' "$FULL")
ACT_P1=$(jq -c '[.[].observed_time_unix_nano]' "$P1")
[[ "$ACT_P1" == "$EXP_P1" ]] || { echo "page1 != full[0:3]; exp=$EXP_P1 act=$ACT_P1" >&2; exit 1; }

# Page 2 must be exactly records [3:6) of the full ordered set.
EXP_P2=$(jq -c '[.[].observed_time_unix_nano][3:6]' "$FULL")
ACT_P2=$(jq -c '[.[].observed_time_unix_nano]' "$P2")
[[ "$ACT_P2" == "$EXP_P2" ]] || { echo "page2 != full[3:6]; exp=$EXP_P2 act=$ACT_P2" >&2; exit 1; }

# Page 1 and Page 2 must be disjoint (offset genuinely skipped).
OVERLAP=$(jq -n --argjson a "$ACT_P1" --argjson b "$ACT_P2" '$a - ($a - $b) | length')
[[ "$OVERLAP" == "0" ]] || { echo "page1 and page2 overlap by $OVERLAP records" >&2; exit 1; }

# Invalid limit=0 must be 400 "invalid limit".
[[ "$(code inv_code)" == "400" ]] || { echo "limit=0 expected 400, got $(code inv_code)" >&2; exit 1; }
INV_ERR=$(jq -r '.error' "$INV")
[[ "$INV_ERR" == "invalid limit" ]] || { echo "limit=0 reason expected 'invalid limit', got '$INV_ERR'" >&2; exit 1; }

# Offset past end must be the empty array (not an error).
PAST_COUNT=$(jq 'length' "$PAST")
[[ "$PAST_COUNT" == "0" ]] || { echo "offset past end expected [], got $PAST_COUNT" >&2; exit 1; }

echo "OK — pagination: total=${TOTAL}; limit=3 returns full[0:3]; offset=3&limit=3 returns full[3:6] (disjoint); limit=0 -> 400 'invalid limit'; offset past end -> []"
