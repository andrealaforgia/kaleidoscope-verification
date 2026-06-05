#!/usr/bin/env bash
# Q05 — query-api rejects an invalid REGEX matcher with an honest 400
# status:error and never echoes the offending pattern.
#
# A `=~` matcher carries a raw regex compiled filter-side; "A compile
# failure is the single origin of the invalid-regex 400... the reason
# names the matcher invalid and never echoes the offending pattern"
# (crates/query-api/src/lib.rs:191). build_filter runs BEFORE the store
# query, so an empty store suffices (no ingest).
#
# Given query-api is running
# When query_range is called with `gen{job=~"<bad-regex>"}` (an unclosed
#      char class)
# Then it returns HTTP 400, `status:error`, a non-empty reason, and the
#      body does NOT contain the offending pattern (no echo).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="q05-$$"
docker run --rm -d --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19095:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
# Valid selector syntax, invalid regex: ZZRELEAKZZ[ has an unclosed
# character class. Parses as a Matches matcher, then fails to compile.
CODE=$(curl -G -sS -o "/tmp/q05.json" -w "%{http_code}" \
    --data-urlencode "query=gen{job=~\"ZZRELEAKZZ[\"}" \
    --data-urlencode "start=1700000000" \
    --data-urlencode "end=1700000100" \
    --data-urlencode "step=15s" \
    "http://localhost:19095/api/v1/query_range")
echo "http_code=$CODE"
cp /tmp/q05.json "'"$EVIDENCE_DIR"'/q05-response.json"
echo "body=$(cat /tmp/q05.json)"
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" Q05 "$INLINE"

R="$EVIDENCE_DIR/q05-response.json"
CODE=$(grep -oE "http_code=[0-9]+" "$EVIDENCE_DIR/Q05.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$CODE" == "400" ]] || { echo "FAIL: expected 400, got $CODE" >&2; cat "$R" >&2; exit 1; }
S=$(jq -r '.status' "$R" 2>/dev/null)
[[ "$S" == "error" ]] || { echo "FAIL: status=$S (expected error)" >&2; cat "$R" >&2; exit 1; }
REASON=$(jq -r '.error // empty' "$R" 2>/dev/null)
[[ -n "$REASON" ]] || { echo "FAIL: no error reason" >&2; cat "$R" >&2; exit 1; }
# No-echo: the offending pattern token must not appear in the body.
grep -q 'ZZRELEAKZZ' "$R" \
    && { echo "FAIL: response echoed the offending regex pattern (ZZRELEAKZZ leaked)" >&2; cat "$R" >&2; exit 1; }

echo "OK — query-api rejects an invalid regex matcher with 400 status:error (reason: ${REASON}) and does NOT echo the offending pattern (ZZRELEAKZZ absent from the body)."
