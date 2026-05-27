#!/usr/bin/env bash
# Q02 — `query-api` refuses an oversized window with an honest
# 400 status:error rather than truncating silently. Anchors the
# cap contract from `feat(read-caps)` (commit b71ad8a) and
# ADR-0050 Decision 1 / D5: the window cap is 86400 seconds
# (24 h); the store is NEVER queried on the refusal path; the
# reason names the cap value verbatim.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="q02-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 9090:9090 \
    "$QAPI_IMAGE" > /dev/null
# Give the listener a moment to bind.
sleep 3

# Ask for a window of (86401) seconds — one second over the cap.
START=1700000000
END=$((START + 86401))
HTTP_CODE=$(curl -sS -o "'"$EVIDENCE_DIR"'/q02-response.json" -w "%{http_code}" \
    "http://localhost:9090/api/v1/query_range?query=gen&start=${START}&end=${END}&step=15s")
echo "http_code=${HTTP_CODE}"
echo "---response---"
cat "'"$EVIDENCE_DIR"'/q02-response.json"
echo
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" Q02 "$INLINE"

HTTP_CODE=$(grep -oE "http_code=[0-9]+" "$EVIDENCE_DIR/Q02.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$HTTP_CODE" == "400" ]] || { echo "expected http 400, got: $HTTP_CODE" >&2; exit 1; }
STATUS=$(jq -r '.status' "$EVIDENCE_DIR/q02-response.json")
[[ "$STATUS" == "error" ]] || { echo "expected status=error, got: $STATUS" >&2; cat "$EVIDENCE_DIR/q02-response.json" >&2; exit 1; }
ERROR=$(jq -r '.error' "$EVIDENCE_DIR/q02-response.json")
echo "$ERROR" | grep -qE "86400" || { echo "error message lacks cap value 86400: $ERROR" >&2; exit 1; }
echo "OK — query-api refuses (end - start) > 86400 with 400 status=error; reason: $ERROR"
