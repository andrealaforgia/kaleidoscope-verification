#!/usr/bin/env bash
# TQ01 — `trace-query-api` rejects a malformed `trace_id` on the
# lookup-by-id arm with an honest 400 "invalid trace_id", and the
# store is never touched on that path; a well-formed 32-hex id is
# NOT rejected (it reaches the store and returns 200 on the empty
# Ray store). Opens the TQ surface. Anchors ADR-0053 Decision 2
# (`/api/v1/traces/by_id?trace_id=<32-hex>`, case-insensitive;
# missing/empty/wrong-length/non-hex all collapse to the single
# literal 400 reason, raw value never echoed).
#
# Three-shot on a freshly opened EMPTY Ray store with a resolved
# tenant:
#   (a) non-hex trace_id      -> 400 "invalid trace_id"
#   (b) wrong-length trace_id -> 400 "invalid trace_id"
#   (c) valid 32-hex (absent) -> 200 (proves the 400 is the parse
#       arm, not a blanket rejection; an absent id is Ok(empty))
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="tq01-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19095:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 3

BASE="http://localhost:19095/api/v1/traces/by_id"

# (a) non-hex (32 chars but not hex)
CODE_A=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq01-a-nonhex.json" -w "%{http_code}" \
    "$BASE" --data-urlencode "trace_id=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
echo "code_a_nonhex=${CODE_A}"

# (b) wrong length (too short)
CODE_B=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq01-b-shortlen.json" -w "%{http_code}" \
    "$BASE" --data-urlencode "trace_id=abc123")
echo "code_b_shortlen=${CODE_B}"

# (c) valid 32-hex, absent from the empty store
CODE_C=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/tq01-c-valid.json" -w "%{http_code}" \
    "$BASE" --data-urlencode "trace_id=0123456789abcdef0123456789abcdef")
echo "code_c_valid=${CODE_C}"
echo "---a body---"; cat "'"$EVIDENCE_DIR"'/tq01-a-nonhex.json"; echo
echo "---b body---"; cat "'"$EVIDENCE_DIR"'/tq01-b-shortlen.json"; echo
docker logs "$NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-trace-query-api.sh" "$EVIDENCE_DIR" TQ01 "$INLINE"

OUT="$EVIDENCE_DIR/TQ01.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
CA=$(code code_a_nonhex); CB=$(code code_b_shortlen); CC=$(code code_c_valid)

[[ "$CA" == "400" ]] || { echo "non-hex trace_id expected 400, got: $CA" >&2; exit 1; }
[[ "$CB" == "400" ]] || { echo "wrong-length trace_id expected 400, got: $CB" >&2; exit 1; }
[[ "$CC" == "200" ]] || { echo "valid 32-hex trace_id expected 200, got: $CC" >&2; exit 1; }

for f in tq01-a-nonhex tq01-b-shortlen; do
    STATUS=$(jq -r '.status' "$EVIDENCE_DIR/$f.json")
    [[ "$STATUS" == "error" ]] || { echo "$f expected status=error, got: $STATUS" >&2; cat "$EVIDENCE_DIR/$f.json" >&2; exit 1; }
    ERR=$(jq -r '.error' "$EVIDENCE_DIR/$f.json")
    [[ "$ERR" == "invalid trace_id" ]] || { echo "$f reason expected 'invalid trace_id', got: $ERR" >&2; exit 1; }
    # The redaction contract: the raw value is NEVER echoed.
    echo "$ERR" | grep -qE 'zzzz|abc123' && { echo "$f leaked the raw trace_id into the reason" >&2; exit 1; }
done

echo "OK — trace-query-api by-id rejects non-hex and wrong-length trace_id with 400 'invalid trace_id' (raw never echoed); a valid 32-hex id is accepted (200) on the empty store"
