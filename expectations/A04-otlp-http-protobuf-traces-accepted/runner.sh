#!/usr/bin/env bash
# A04 — OTLP/HTTP/protobuf traces accepted on :4318.
#
# Same shape as A01 but driving telemetrygen's HTTP transport. See
# A01's runner for rationale on why the assertion looks at aperture's
# own stderr (`event=sink_accepted`) rather than the downstream
# otelcol-sink: A01-A06 verify aperture-side acceptance, E01-E03
# verify the round-trip-to-downstream chain.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

TELEMETRYGEN_IMAGE="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
SERVICE_NAME="expectation-A04-pilot"
EXPECTED_SPAN_COUNT=2

echo "step 1: waiting for aperture /readyz"
DEADLINE=$(( SECONDS + 30 ))
while (( SECONDS < DEADLINE )); do
    code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' \
                 http://localhost:4318/readyz 2>/dev/null || echo "")"
    if [[ "$code" == "200" ]]; then
        echo "  aperture ready"
        break
    fi
    sleep 1
done
if [[ "${code:-}" != "200" ]]; then
    echo "aperture never became ready" >&2
    exit 1
fi

echo "step 2: sending one OTLP/HTTP/protobuf trace via telemetrygen"
docker run --rm --network "$COMPOSE_NETWORK" \
    "$TELEMETRYGEN_IMAGE" \
    traces \
        --otlp-http \
        --otlp-endpoint=aperture:4318 \
        --otlp-insecure \
        --traces=1 \
        --otlp-attributes "service.name=\"${SERVICE_NAME}\"" \
    > "$EVIDENCE_DIR/telemetrygen.stdout.txt" \
    2> "$EVIDENCE_DIR/telemetrygen.stderr.txt"
echo "  telemetrygen exited 0"

sleep 1
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

echo "step 3: checking aperture stderr for sink_accepted line"
ACCEPT_LINE="$(grep -F '"event":"sink_accepted"' "$EVIDENCE_DIR/aperture.live.stderr.txt" \
                 | grep -F "\"signal\":\"traces\"" \
                 | grep -F "\"resource.service.name\":\"${SERVICE_NAME}\"" || true)"

if [[ -z "$ACCEPT_LINE" ]]; then
    echo "no sink_accepted line for service ${SERVICE_NAME} traces in aperture stderr" >&2
    exit 1
fi
echo "  found: ${ACCEPT_LINE}"

OBSERVED_SPAN_COUNT="$(printf '%s' "$ACCEPT_LINE" \
                       | sed -n 's/.*"span_count":\([0-9]*\).*/\1/p')"
if [[ -z "$OBSERVED_SPAN_COUNT" ]]; then
    echo "could not extract span_count from sink_accepted line" >&2
    exit 1
fi
echo "  observed span_count=${OBSERVED_SPAN_COUNT}, expected=${EXPECTED_SPAN_COUNT}"
if [[ "$OBSERVED_SPAN_COUNT" != "$EXPECTED_SPAN_COUNT" ]]; then
    echo "span_count mismatch: aperture saw ${OBSERVED_SPAN_COUNT}, telemetrygen sent ${EXPECTED_SPAN_COUNT}" >&2
    exit 1
fi

echo "OK — aperture acked the OTLP/HTTP/protobuf request and emitted sink_accepted with matching span_count and service.name"
