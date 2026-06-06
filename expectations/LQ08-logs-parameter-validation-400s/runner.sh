#!/usr/bin/env bash
# LQ08 — log-query-api validates query parameters and returns 400 (never
# 500) on each malformed case, before touching the store. Covers
# UC-LOG-004 (unknown min_severity), UC-LOG-006 (empty body_contains),
# UC-LOG-007 (oversized body_contains > 1024 bytes), UC-LOG-009
# (uncompilable body_regex -> 400 not 500), UC-LOG-015 (window > 86400 s).
#
# Validation precedes the query, so an empty store suffices: only a valid
# baseline request is expected to reach the (empty) store and return 200.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
LQ_NAME="lq08-lqapi-$$"
cleanup() { docker stop --time 5 "$LQ_NAME" >/dev/null 2>&1 || true; docker rm "$LQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$LQ_NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19121:9091 "$LQAPI_IMAGE" > /dev/null
for i in $(seq 1 30); do
    curl -sS --max-time 2 -o /dev/null "http://localhost:19121/api/v1/logs?start=0&end=100" 2>/dev/null && break
    sleep 0.5
done

U="http://localhost:19121/api/v1/logs"
code() { curl -sS -o /dev/null -w "%{http_code}" -G "$U" "$@"; }
BIG=$(printf "x%.0s" $(seq 1 1100))

{
  echo "unknown_severity=$(code --data-urlencode start=0 --data-urlencode end=100 --data-urlencode min_severity=LOUD)"
  echo "empty_body_contains=$(code --data-urlencode start=0 --data-urlencode end=100 --data-urlencode body_contains=)"
  echo "oversized_body_contains=$(code --data-urlencode start=0 --data-urlencode end=100 --data-urlencode body_contains=$BIG)"
  echo "invalid_regex=$(code --data-urlencode start=0 --data-urlencode end=100 --data-urlencode body_regex=[)"
  echo "window_over_cap=$(code --data-urlencode start=0 --data-urlencode end=90000)"
  echo "valid_baseline=$(code --data-urlencode start=0 --data-urlencode end=100)"
} | tee "'"$EVIDENCE_DIR"'/codes.txt"
'
"$HARNESS_DIR/run-log-query-api.sh" "$EVIDENCE_DIR" LQ08 "$INLINE"

C="$EVIDENCE_DIR/codes.txt"
val() { grep -oE "$1=[0-9]+" "$C" | tail -1 | cut -d= -f2; }
for k in unknown_severity empty_body_contains oversized_body_contains invalid_regex window_over_cap; do
    [[ "$(val "$k")" == "400" ]] || { echo "FAIL: $k expected 400, got $(val "$k")" >&2; exit 1; }
done
[[ "$(val valid_baseline)" == "200" ]] || { echo "FAIL: valid baseline expected 200, got $(val valid_baseline)" >&2; exit 1; }
echo "OK — unknown severity / empty + oversized body_contains / invalid regex / over-cap window all 400; valid baseline 200"
