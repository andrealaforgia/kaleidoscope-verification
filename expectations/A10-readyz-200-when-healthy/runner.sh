#!/usr/bin/env bash
# A10 — GET /readyz returns 200 in normal operation.
#
# Polls aperture's HTTP probe up to a 30 s deadline; expectation is
# satisfied iff aperture answers 200 within the window. The body is
# captured verbatim into evidence/readyz.body.txt so the exact bytes
# are citable.

set -euo pipefail
EVIDENCE_DIR="$1"

URL="http://localhost:4318/readyz"
DEADLINE=$(( SECONDS + 30 ))
attempt=0
CODE=""

# Erase prior captures so an interrupted previous run does not leak.
: > "$EVIDENCE_DIR/readyz.body.txt"
: > "$EVIDENCE_DIR/readyz.curl.stderr"

while (( SECONDS < DEADLINE )); do
    attempt=$((attempt + 1))
    CODE="$(curl -sS --max-time 2 \
                 -o "$EVIDENCE_DIR/readyz.body.txt" \
                 -w '%{http_code}' \
                 "$URL" 2>>"$EVIDENCE_DIR/readyz.curl.stderr" || echo "curl-exit-$?")"
    echo "attempt ${attempt}: code=${CODE}"
    if [[ "$CODE" == "200" ]]; then
        break
    fi
    sleep 1
done

printf '%s\n' "$CODE" > "$EVIDENCE_DIR/readyz.code.txt"
echo "final attempts: ${attempt}"
echo "final code:     ${CODE}"
echo "body bytes:"
od -c "$EVIDENCE_DIR/readyz.body.txt" | head -5

if [[ "$CODE" != "200" ]]; then
    echo "expected HTTP 200 from ${URL}, got '${CODE}'" >&2
    exit 1
fi
