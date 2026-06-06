#!/usr/bin/env bash
# A08 — POST garbage to /v1/traces with Content-Type
# application/x-protobuf, expect HTTP 400 plus a body that names a
# recognisable OtlpViolation Rule discriminator. Anchors at
# slice-03-traces.md L44 ("`POST /v1/traces` with logs bytes -> HTTP
# 400, body contains `rule=...`, ...").

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

URL="http://localhost:4318/v1/traces"

# 1. Wait for aperture readiness.
echo "step 1: waiting for aperture /readyz=200"
DEADLINE=$(( SECONDS + 30 ))
while (( SECONDS < DEADLINE )); do
    code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' \
                 http://localhost:4318/readyz 2>/dev/null || echo "")"
    [[ "$code" == "200" ]] && { echo "  aperture ready"; break; }
    sleep 1
done
[[ "${code:-}" == "200" ]] || { echo "aperture never became ready" >&2; exit 1; }

# 2. POST garbage bytes to /v1/traces. The body is intentionally not
#    a valid protobuf-encoded ExportTraceServiceRequest.
echo "step 2: POST 32 random-looking garbage bytes to ${URL} (authenticated)"
# Mandatory ingest auth (N29): attach a valid bearer so the malformed
# body reaches the protobuf parser (400), rather than being 401'd at the
# door before any body work. The contract under test is body validation,
# not auth — A20 owns the auth-reject contract.
JWT="$("$HARNESS_DIR/mint-ingest-jwt.sh")"
GARBAGE_BYTES=$'\xff\x00\xff\x01\x02\x03this-is-not-protobuf-bytes\xfe'
RESPONSE_CODE="$(curl -sS --max-time 5 \
                 -o "$EVIDENCE_DIR/response.body.txt" \
                 -w '%{http_code}' \
                 -X POST \
                 -H 'Content-Type: application/x-protobuf' \
                 -H "Authorization: Bearer ${JWT}" \
                 --data-binary "$GARBAGE_BYTES" \
                 "$URL")"

printf '%s\n' "$RESPONSE_CODE" > "$EVIDENCE_DIR/response.code.txt"
echo "  response code: ${RESPONSE_CODE}"
echo "  response body (first 300 bytes):"
head -c 300 "$EVIDENCE_DIR/response.body.txt"; echo

# 3. Assertions.
if [[ "$RESPONSE_CODE" != "400" ]]; then
    echo "expected HTTP 400, got '${RESPONSE_CODE}'" >&2
    exit 1
fi

# The harness's OtlpViolation::Display vocabulary names a Rule by one
# of the documented discriminators (per the source feed and the
# slice-03 contract). Accept any of them; the body should mention at
# least one.
if ! grep -qE 'EmptyInput|ProtobufDecode|SignalMismatch|rule=|invalid' "$EVIDENCE_DIR/response.body.txt"; then
    echo "response body does not name an OtlpViolation Rule discriminator" >&2
    exit 1
fi

# 4. Capture aperture's live stderr so the request_received line
#    (with bytes count and signal) is preserved as evidence.
sleep 1
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

echo "OK — HTTP 400 with body containing a Rule discriminator"
