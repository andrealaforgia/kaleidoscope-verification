#!/usr/bin/env bash
# LQ03 — a log emitted with a known body round-trips through the
# kaleidoscope-gateway into Lumen and is then selectable by
# log-query-api's `body_regex` filter, with REGEX semantics (not
# mere substring): the SAME body is matched by one pattern and
# missed by a stricter quantifier on the same characters.
#
# Body is "lq03-needle-ziggurat" (contains "ziggurat" = ...iggu...).
#   match  regex `ig{2}u`  -> matches "iggu"  -> non-empty
#   absent regex `ig{3}u`  -> needs three g's -> []
# A substring filter could not express `{2}` vs `{3}`; the only way
# the absent query returns [] while the match query returns rows is
# if the regex engine is genuinely applied. Anchors ADR-0056
# (body_regex), feat 6cecd63.
#
# Crosses gateway -> Lumen -> log-query-api, same fixture as LQ02.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NEEDLE_BODY="lq03-needle-ziggurat"
MATCH_RE="ig{2}u"
ABSENT_RE="ig{3}u"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq03-gw-$$"
LQ_NAME="lq03-lqapi-$$"

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
    -p 14319:4318 \
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
    --otlp-endpoint localhost:14319 \
    --otlp-insecure \
    --otlp-http \
    --duration 2s \
    --rate 5 \
    --body "$NEEDLE_BODY" \
    --otlp-attributes service.name=\"lq03-pilot\" \
    > /tmp/tg3.out 2> /tmp/tg3.err || { echo "telemetrygen failed" >&2; cat /tmp/tg3.err >&2; exit 1; }
cp /tmp/tg3.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"

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
    -p 19092:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
URL="http://localhost:19092/api/v1/logs"

# Step 5: matching regex. Use -G --data-urlencode so the regex
# metacharacters { } survive into the query string intact.
curl -sS -G -o "'"$EVIDENCE_DIR"'/lq03-match.json" -w "match_code=%{http_code}\n" \
    "$URL" \
    --data-urlencode "start=${START}" \
    --data-urlencode "end=${END}" \
    --data-urlencode "body_regex=${MATCH_RE}"
# Step 6: stricter (absent) regex on the same characters.
curl -sS -G -o "'"$EVIDENCE_DIR"'/lq03-absent.json" -w "absent_code=%{http_code}\n" \
    "$URL" \
    --data-urlencode "start=${START}" \
    --data-urlencode "end=${END}" \
    --data-urlencode "body_regex=${ABSENT_RE}"

docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
echo "body=$NEEDLE_BODY match_re=$MATCH_RE absent_re=$ABSENT_RE"
echo "---match head---"; head -c 400 "'"$EVIDENCE_DIR"'/lq03-match.json"; echo
echo "---absent head---"; head -c 200 "'"$EVIDENCE_DIR"'/lq03-absent.json"; echo
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ03 "$INLINE"

MATCH="$EVIDENCE_DIR/lq03-match.json"
ABSENT_F="$EVIDENCE_DIR/lq03-absent.json"

MC=$(grep -oE 'match_code=[0-9]+' "$EVIDENCE_DIR/LQ03.stdout.txt" | tail -1 | cut -d= -f2)
AC=$(grep -oE 'absent_code=[0-9]+' "$EVIDENCE_DIR/LQ03.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$MC" == "200" ]] || { echo "match regex query expected 200, got: $MC" >&2; exit 1; }
[[ "$AC" == "200" ]] || { echo "absent regex query expected 200, got: $AC" >&2; exit 1; }

# Matching regex must return >=1 record, and every returned record's
# body must contain "iggu" (the substring ig{2}u selects).
MATCH_COUNT=$(jq 'length' "$MATCH")
[[ "$MATCH_COUNT" -ge 1 ]] || { echo "match regex returned no records; body_regex did not round-trip" >&2; cat "$MATCH" >&2; exit 1; }
NON_MATCHING=$(jq '[.[] | select((.body | test("ig{2}u")) | not)] | length' "$MATCH")
[[ "$NON_MATCHING" == "0" ]] || { echo "match regex returned $NON_MATCHING records whose body fails ig{2}u" >&2; cat "$MATCH" >&2; exit 1; }

# The stricter regex on the same bodies must return [].
ABSENT_COUNT=$(jq 'length' "$ABSENT_F")
[[ "$ABSENT_COUNT" == "0" ]] || { echo "stricter regex ig{3}u expected [], got $ABSENT_COUNT records" >&2; cat "$ABSENT_F" >&2; exit 1; }

echo "OK — log body round-trips gateway->Lumen->log-query-api; body_regex=ig{2}u returns ${MATCH_COUNT} record(s) all matching, while the stricter ig{3}u on the same bodies returns [] (proves regex semantics, not substring)"
