#!/usr/bin/env bash
# Q04 — query-api rejects a malformed PromQL query with an honest 400
# status:error AND never echoes the raw query back.
#
# selector::parse is the first validation after tenancy/bounds; an empty
# query, an unterminated brace, or unrecognised matcher syntax each yield
# a 400 with a human-readable reason. The reason "NEVER echoes the raw
# query" (crates/query-api/src/selector.rs:75) — an injection/leak guard.
# The store is never touched on this path, so no ingest is needed.
#
# Given query-api is running
# When query_range is called with a malformed `query`
# Then it returns HTTP 400, `status:error`, a non-empty reason, and the
#      body does NOT contain the raw query text (no echo).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="q04-$$"
docker run --rm -d --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19094:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
URL="http://localhost:19094/api/v1/query_range"
ask() { # $1=label $2=query
    local code
    code=$(curl -G -sS -o "/tmp/q04-$1.json" -w "%{http_code}" \
        --data-urlencode "query=$2" \
        --data-urlencode "start=1700000000" \
        --data-urlencode "end=1700000100" \
        --data-urlencode "step=15s" "$URL")
    echo "code_$1=$code"
    cp "/tmp/q04-$1.json" "'"$EVIDENCE_DIR"'/q04-$1.json"
    echo "body_$1=$(cat /tmp/q04-$1.json)"
}
ask empty ""
ask brace "ZZLEAKZZ{"
ask syntax "gen{@@@}"
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" Q04 "$INLINE"

OUT="$EVIDENCE_DIR/Q04.stdout.txt"
code() { grep -oE "code_$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

for k in empty brace syntax; do
    [[ "$(code "$k")" == "400" ]] || { echo "FAIL: '$k' query expected 400, got $(code "$k")" >&2; cat "$EVIDENCE_DIR/q04-$k.json" >&2; exit 1; }
    s=$(jq -r '.status' "$EVIDENCE_DIR/q04-$k.json" 2>/dev/null)
    [[ "$s" == "error" ]] || { echo "FAIL: '$k' status=$s (expected error)" >&2; cat "$EVIDENCE_DIR/q04-$k.json" >&2; exit 1; }
    r=$(jq -r '.error // empty' "$EVIDENCE_DIR/q04-$k.json" 2>/dev/null)
    [[ -n "$r" ]] || { echo "FAIL: '$k' carried no error reason" >&2; cat "$EVIDENCE_DIR/q04-$k.json" >&2; exit 1; }
done
# No-echo: the distinctive raw token in the 'brace' query must NOT appear
# anywhere in the response body.
grep -q 'ZZLEAKZZ' "$EVIDENCE_DIR/q04-brace.json" \
    && { echo "FAIL: response echoed the raw query token ZZLEAKZZ (query leak)" >&2; cat "$EVIDENCE_DIR/q04-brace.json" >&2; exit 1; }

echo "OK — query-api rejects malformed PromQL with honest 400 status:error and a reason, and does NOT echo the raw query (empty/unterminated-brace/unrecognised-syntax all 400; the ZZLEAKZZ canary did not leak into the body)."
