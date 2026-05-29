#!/usr/bin/env bash
# LQ02 — a log emitted with a known body round-trips through the
# kaleidoscope-gateway into the durable Lumen store and is then
# selectable by log-query-api's `body_contains` filter: a query
# whose substring matches the body returns the record; a query
# whose substring does NOT match returns the empty array. This
# proves the body filter actually FILTERS (LQ01 only proved the
# two filters are mutually exclusive at parse time).
#
# Crosses gateway -> Lumen -> log-query-api. End-to-end, like EG01
# but on the logs pillar and the log read API. Anchors ADR-0055
# (body_contains) at the running surface, feat 1bfa609.
#
# Scenario:
#   1. gateway up, writable /data, KALEIDOSCOPE_DEFAULT_TENANT=acme.
#   2. telemetrygen logs --body "<NEEDLE>" at :4318 (OTLP/HTTP).
#   3. SIGTERM gateway so Lumen flushes.
#   4. log-query-api up on the SAME /data, tenant=acme, :9091.
#   5. GET /api/v1/logs?...&body_contains=<NEEDLE> -> non-empty,
#      every returned record's body contains NEEDLE.
#   6. GET /api/v1/logs?...&body_contains=<ABSENT> -> [].
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NEEDLE="lq02-needle-ziggurat"
ABSENT="lq02-absent-qwerty"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq02-gw-$$"
LQ_NAME="lq02-lqapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Step 1: gateway up.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14318:4318 \
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

# Step 2: emit logs carrying the known body.
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    logs \
    --otlp-endpoint localhost:14318 \
    --otlp-insecure \
    --otlp-http \
    --duration 2s \
    --rate 5 \
    --body "$NEEDLE" \
    --otlp-attributes service.name=\"lq02-pilot\" \
    > /tmp/tg.out 2> /tmp/tg.err || { echo "telemetrygen failed" >&2; cat /tmp/tg.err >&2; exit 1; }
cp /tmp/tg.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"

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
    -p 19091:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
BASE="http://localhost:19091/api/v1/logs?start=${START}&end=${END}"

# Step 5: matching substring.
curl -sS -o "'"$EVIDENCE_DIR"'/lq02-match.json" -w "match_code=%{http_code}\n" \
    "${BASE}&body_contains=${NEEDLE}"
# Step 6: absent substring.
curl -sS -o "'"$EVIDENCE_DIR"'/lq02-absent.json" -w "absent_code=%{http_code}\n" \
    "${BASE}&body_contains=${ABSENT}"

docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
echo "needle=$NEEDLE absent=$ABSENT"
echo "---match head---"; head -c 400 "'"$EVIDENCE_DIR"'/lq02-match.json"; echo
echo "---absent head---"; head -c 200 "'"$EVIDENCE_DIR"'/lq02-absent.json"; echo
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ02 "$INLINE"

MATCH="$EVIDENCE_DIR/lq02-match.json"
ABSENT_F="$EVIDENCE_DIR/lq02-absent.json"
NEEDLE="lq02-needle-ziggurat"

MC=$(grep -oE 'match_code=[0-9]+' "$EVIDENCE_DIR/LQ02.stdout.txt" | tail -1 | cut -d= -f2)
AC=$(grep -oE 'absent_code=[0-9]+' "$EVIDENCE_DIR/LQ02.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$MC" == "200" ]] || { echo "match query expected 200, got: $MC" >&2; exit 1; }
[[ "$AC" == "200" ]] || { echo "absent query expected 200, got: $AC" >&2; exit 1; }

# The matching query must return at least one record, and EVERY
# returned record's body must contain the needle (proves the
# filter is applied, not bypassed).
MATCH_COUNT=$(jq 'length' "$MATCH")
[[ "$MATCH_COUNT" -ge 1 ]] || { echo "match query returned no records; body filter did not round-trip" >&2; cat "$MATCH" >&2; exit 1; }
NON_MATCHING=$(jq --arg n "$NEEDLE" '[.[] | select((.body | contains($n)) | not)] | length' "$MATCH")
[[ "$NON_MATCHING" == "0" ]] || { echo "match query returned $NON_MATCHING records whose body lacks the needle" >&2; cat "$MATCH" >&2; exit 1; }

# The absent query must return the empty array.
ABSENT_COUNT=$(jq 'length' "$ABSENT_F")
[[ "$ABSENT_COUNT" == "0" ]] || { echo "absent-substring query expected [], got $ABSENT_COUNT records" >&2; cat "$ABSENT_F" >&2; exit 1; }

echo "OK — log body round-trips gateway->Lumen->log-query-api; body_contains=${NEEDLE} returns ${MATCH_COUNT} matching record(s), all bodies contain the needle; a non-matching substring returns []"
