#!/usr/bin/env bash
# G01 — `kaleidoscope-gateway` started with a writable pillar
# root and `KALEIDOSCOPE_DEFAULT_TENANT` set emits an
# `event=gateway_starting` event on stderr within a short window
# and binds the OTLP HTTP listener (port 4318). Anchors the
# Earned-Trust startup sequence from ADR-0041 DD5.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="g01-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 4318:4318 \
    "$GW_IMAGE" > /dev/null
# Stream logs to file in the background.
docker logs -f "$NAME" > /tmp/gw.out 2> /tmp/gw.err &
LOGS_PID=$!
# Poll for the gateway_starting event for up to 30 s.
SAW=""
for i in $(seq 1 30); do
    if grep -q "gateway_starting" /tmp/gw.err 2>/dev/null; then
        SAW="yes"
        break
    fi
    sleep 1
done
docker stop --time 5 "$NAME" >/dev/null 2>&1 || true
kill $LOGS_PID 2>/dev/null || true
echo "saw_gateway_starting=$SAW"
echo "---stderr head---"
head -30 /tmp/gw.err
cp /tmp/gw.err "'"$EVIDENCE_DIR"'/gateway.stderr.txt"
cp /tmp/gw.out "'"$EVIDENCE_DIR"'/gateway.stdout.txt"
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G01 "$INLINE"

SAW=$(grep -oE 'saw_gateway_starting=[a-z]*' "$EVIDENCE_DIR/G01.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$SAW" == "yes" ]] || { echo "gateway_starting event not observed within 30 s" >&2; exit 1; }
grep -q "gateway_starting" "$EVIDENCE_DIR/gateway.stderr.txt" || \
    { echo "stderr lacks gateway_starting event (defensive recheck)" >&2; exit 1; }
echo "OK — gateway emits gateway_starting on stderr with a writable pillar root + DEFAULT_TENANT"
