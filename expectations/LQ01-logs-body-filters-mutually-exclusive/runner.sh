#!/usr/bin/env bash
# LQ01 — `log-query-api` refuses a request that carries BOTH
# `body_contains` and `body_regex` with an honest 400 status:error,
# and the store is never queried on that path. Anchors the
# mutual-exclusion contract from ADR-0056 Decision 7 / DD4
# (commit ca25818 design, 6cecd63 feat): the two body filters are
# siblings, exactly one may be present.
#
# The test is a tight three-shot on a freshly-opened EMPTY Lumen
# store with a resolved tenant:
#   (a) single body_contains  -> 200  (proves body filters ARE
#       accepted on this path, so the 400 below is specifically the
#       mutual-exclusion arm and not a blanket rejection),
#   (b) single body_regex      -> 200  (the sibling, same proof),
#   (c) both at once           -> 400 status:error with the literal
#       reason "specify body_regex or body_contains, not both".
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="lq01-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 9091:9091 \
    "$LQAPI_IMAGE" > /dev/null
# Give the listener a moment to bind (probe + open store first).
sleep 3

START=1700000000
END=$((START + 3600))
BASE="http://localhost:9091/api/v1/logs?start=${START}&end=${END}"

# (a) single body_contains
CODE_A=$(curl -sS -o "'"$EVIDENCE_DIR"'/lq01-a-contains.json" -w "%{http_code}" \
    "${BASE}&body_contains=hello")
echo "code_a_contains=${CODE_A}"

# (b) single body_regex
CODE_B=$(curl -sS -o "'"$EVIDENCE_DIR"'/lq01-b-regex.json" -w "%{http_code}" \
    "${BASE}&body_regex=hel.o")
echo "code_b_regex=${CODE_B}"

# (c) both at once -> mutual-exclusion 400
CODE_C=$(curl -sS -o "'"$EVIDENCE_DIR"'/lq01-c-both.json" -w "%{http_code}" \
    "${BASE}&body_contains=hello&body_regex=hel.o")
echo "code_c_both=${CODE_C}"
echo "---both response---"
cat "'"$EVIDENCE_DIR"'/lq01-c-both.json"
echo
docker logs "$NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-log-query-api.sh" "$EVIDENCE_DIR" LQ01 "$INLINE"

OUT="$EVIDENCE_DIR/LQ01.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

CODE_A=$(code code_a_contains)
CODE_B=$(code code_b_regex)
CODE_C=$(code code_c_both)

[[ "$CODE_A" == "200" ]] || { echo "single body_contains expected 200, got: $CODE_A" >&2; exit 1; }
[[ "$CODE_B" == "200" ]] || { echo "single body_regex expected 200, got: $CODE_B" >&2; exit 1; }
[[ "$CODE_C" == "400" ]] || { echo "both filters expected 400, got: $CODE_C" >&2; exit 1; }

STATUS=$(jq -r '.status' "$EVIDENCE_DIR/lq01-c-both.json")
[[ "$STATUS" == "error" ]] || { echo "expected status=error on both, got: $STATUS" >&2; cat "$EVIDENCE_DIR/lq01-c-both.json" >&2; exit 1; }
ERROR=$(jq -r '.error' "$EVIDENCE_DIR/lq01-c-both.json")
[[ "$ERROR" == "specify body_regex or body_contains, not both" ]] || \
    { echo "unexpected mutual-exclusion reason: $ERROR" >&2; exit 1; }

echo "OK — log-query-api accepts each body filter alone (200/200) and refuses both together (400 status=error: \"$ERROR\")"
