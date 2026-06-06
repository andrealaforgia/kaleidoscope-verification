#!/usr/bin/env bash
# Q09 — query-api request-shape contracts that need no data:
#   - a query matching nothing is SUCCESS with an empty result, not
#     404/500 (UC-MET-007);
#   - non-numeric start/end -> 400 (UC-MET-014);
#   - float-tolerant epoch seconds (start=1.5) parse without error -> 200
#     (UC-MET-017);
#   - aggregation/rate functions are NOT supported at v0: rate(up[5m])
#     -> 400, the honest raw-selectors-only surface (UC-MET-018).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="q09-$$"
docker run --rm -d --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19131:9090 "$QAPI_IMAGE" > /dev/null
for i in $(seq 1 30); do curl -sS --max-time 2 -o /dev/null "http://localhost:19131/api/v1/query_range?query=up&start=0&end=1&step=15s" 2>/dev/null && break; sleep 0.5; done
U="http://localhost:19131/api/v1/query_range"
code() { curl -sS -o "$1" -w "%{http_code}" -G "$U" "${@:2}"; }

EMPTY_CODE=$(code "'"$EVIDENCE_DIR"'/empty.json" --data-urlencode query=q09doesnotexist --data-urlencode start=1700000000 --data-urlencode end=1700000100 --data-urlencode step=15s)
echo "empty_code=$EMPTY_CODE"
echo "empty_status=$(jq -r .status "'"$EVIDENCE_DIR"'/empty.json")"
echo "empty_len=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/empty.json")"
echo "badtime_code=$(code /tmp/bt.json --data-urlencode query=up --data-urlencode start=abc --data-urlencode end=1700000100 --data-urlencode step=15s)"
# Small window so the only thing under test is float-epoch parsing, not
# the 86400s window cap (UC-MET-010, owned by Q02).
echo "float_code=$(code /tmp/fl.json --data-urlencode query=up --data-urlencode start=1.5 --data-urlencode end=1000 --data-urlencode step=15s)"
echo "rate_code=$(code "'"$EVIDENCE_DIR"'/rate.json" --data-urlencode "query=rate(up[5m])" --data-urlencode start=1700000000 --data-urlencode end=1700000100 --data-urlencode step=15s)"
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" Q09 "$INLINE"

OUT="$EVIDENCE_DIR/Q09.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
[[ "$(val empty_code)" == "200" ]]       || { echo "FAIL: empty query not 200 (got $(val empty_code))" >&2; exit 1; }
[[ "$(val empty_status)" == "success" ]] || { echo "FAIL: empty query not status=success" >&2; exit 1; }
[[ "$(val empty_len)" == "0" ]]          || { echo "FAIL: empty query result not empty" >&2; exit 1; }
[[ "$(val badtime_code)" == "400" ]]     || { echo "FAIL: non-numeric start not 400 (got $(val badtime_code))" >&2; exit 1; }
[[ "$(val float_code)" == "200" ]]       || { echo "FAIL: float epoch 1.5 not accepted (got $(val float_code))" >&2; exit 1; }
[[ "$(val rate_code)" == "400" ]]        || { echo "FAIL: rate(up[5m]) not rejected 400 (got $(val rate_code))" >&2; exit 1; }
echo "OK — nonexistent query is success+empty (200); non-numeric time 400; float epoch 1.5 accepted (200); rate() rejected 400 (no agg at v0)"
