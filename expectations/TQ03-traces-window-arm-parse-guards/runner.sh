#!/usr/bin/env bash
# TQ03 — trace-query-api's window arm GET /api/v1/traces guards its
# inputs BEFORE the store: a missing `service` is the traces-only
# required-parameter 400, an oversized window is the shared
# window-cap 400, and a well-formed request is accepted (200 on the
# empty Ray store). The store is never touched on the two refusal
# paths. Anchors ADR-0048 (service is the one structural divergence
# from logs) + ADR-0050 Decision 1 (window cap 86400s).
#
# Three-shot on a freshly opened EMPTY Ray store with a resolved
# tenant:
#   (a) no `service`            -> 400 "invalid request: service is required"
#   (b) service + window 86401s -> 400 "window exceeds 86400 seconds"
#   (c) service + valid window  -> 200 (empty array; control)
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="tq03-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19098:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 3

URL="http://localhost:19098/api/v1/traces"
START=1700000000

# (a) missing service (valid window, but service is checked first)
CODE_A=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq03-a-noservice.json" -w "%{http_code}" \
    "$URL" --data-urlencode "start=${START}" --data-urlencode "end=$((START+60))")
echo "code_a_noservice=${CODE_A}"

# (b) service present, window one second over the 86400 cap
CODE_B=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq03-b-bigwindow.json" -w "%{http_code}" \
    "$URL" --data-urlencode "service=tq03-pilot" --data-urlencode "start=${START}" --data-urlencode "end=$((START+86401))")
echo "code_b_bigwindow=${CODE_B}"

# (c) service present, valid window
CODE_C=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq03-c-valid.json" -w "%{http_code}" \
    "$URL" --data-urlencode "service=tq03-pilot" --data-urlencode "start=${START}" --data-urlencode "end=$((START+3600))")
echo "code_c_valid=${CODE_C}"
echo "---a---"; cat "'"$EVIDENCE_DIR"'/tq03-a-noservice.json"; echo
echo "---b---"; cat "'"$EVIDENCE_DIR"'/tq03-b-bigwindow.json"; echo
docker logs "$NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-trace-query-api.sh" "$EVIDENCE_DIR" TQ03 "$INLINE"

OUT="$EVIDENCE_DIR/TQ03.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
CA=$(code code_a_noservice); CB=$(code code_b_bigwindow); CC=$(code code_c_valid)

[[ "$CA" == "400" ]] || { echo "missing service expected 400, got: $CA" >&2; exit 1; }
[[ "$CB" == "400" ]] || { echo "oversized window expected 400, got: $CB" >&2; exit 1; }
[[ "$CC" == "200" ]] || { echo "valid request expected 200, got: $CC" >&2; exit 1; }

SA=$(jq -r '.status' "$EVIDENCE_DIR/tq03-a-noservice.json"); EA=$(jq -r '.error' "$EVIDENCE_DIR/tq03-a-noservice.json")
[[ "$SA" == "error" ]] || { echo "(a) expected status=error, got $SA" >&2; exit 1; }
[[ "$EA" == "invalid request: service is required" ]] || { echo "(a) unexpected reason: $EA" >&2; exit 1; }

SB=$(jq -r '.status' "$EVIDENCE_DIR/tq03-b-bigwindow.json"); EB=$(jq -r '.error' "$EVIDENCE_DIR/tq03-b-bigwindow.json")
[[ "$SB" == "error" ]] || { echo "(b) expected status=error, got $SB" >&2; exit 1; }
echo "$EB" | grep -qE '86400' || { echo "(b) window reason lacks cap value 86400: $EB" >&2; exit 1; }

echo "OK — traces window arm guards inputs: missing service -> 400 'invalid request: service is required'; window 86401s -> 400 (reason names 86400); valid service+window -> 200 on the empty store"
