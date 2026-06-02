#!/usr/bin/env bash
# G03 — the gateway's OTLP/HTTP transport gates on Content-Type
# STRICTLY: a non-protobuf media type is refused with 415, and a
# lookalike (`application/x-protobuf-foo`) is NOT conflated with the
# real OTLP media type (`application/x-protobuf`) — no lax `starts_with`.
# A correct `application/x-protobuf` content type with a garbage body is
# NOT a 415 (it is a 400 body-decode error), proving the 415 is
# content-type-specific, not a blanket rejection.
#
# Motivated by the four-quadrants report (Q1: strict content-type
# gating, "no lax starts_with", aperture/src/transport.rs). The gateway
# embeds aperture's HTTP transport on :4318.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="g03-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14330:4318 \
    "$GW_IMAGE" > /dev/null
SAW=""
for i in $(seq 1 30); do
    docker logs "$NAME" 2>&1 | grep -q "listener_bound\|gateway_starting" && { SAW=yes; break; }
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2

URL="http://localhost:14330/v1/metrics"
# (a) application/json -> 415
CODE_JSON=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$URL" \
    -H "Content-Type: application/json" --data-binary "{}")
echo "code_json=$CODE_JSON"
# (b) application/x-protobuf-foo lookalike -> 415 (no lax starts_with).
# Content-type gating runs BEFORE body parsing, so the body is
# irrelevant here; a plain ASCII payload avoids null-byte quoting traps.
CODE_LOOKALIKE=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$URL" \
    -H "Content-Type: application/x-protobuf-foo" --data-binary "xyz")
echo "code_lookalike=$CODE_LOOKALIKE"
# (c) correct application/x-protobuf with a non-protobuf body -> NOT 415
# (it passes the content-type gate, then fails body decode = 400).
CODE_BADPB=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$URL" \
    -H "Content-Type: application/x-protobuf" --data-binary "not-a-valid-protobuf-body")
echo "code_badpb=$CODE_BADPB"
docker logs "$NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker stop --time 5 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G03 "$INLINE"

OUT="$EVIDENCE_DIR/G03.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val code_json)" == "415" ]] || { echo "application/json expected 415, got $(val code_json)" >&2; exit 1; }
[[ "$(val code_lookalike)" == "415" ]] || { echo "application/x-protobuf-foo lookalike expected 415 (no lax starts_with), got $(val code_lookalike)" >&2; exit 1; }
[[ "$(val code_badpb)" != "415" ]] || { echo "application/x-protobuf with bad bytes wrongly 415 (gating is not content-type-specific)" >&2; exit 1; }

echo "OK — strict OTLP/HTTP content-type gating: application/json -> 415, application/x-protobuf-foo lookalike -> 415 (no lax starts_with), application/x-protobuf+garbage -> $(val code_badpb) (NOT 415; content-type-specific)"
