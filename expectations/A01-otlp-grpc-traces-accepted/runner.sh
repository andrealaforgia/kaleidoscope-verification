#!/usr/bin/env bash
# A01 — OTLP/gRPC traces accepted on :4317.
#
# The expectation is aperture-side: aperture acks the client and "the
# configured sink receives ExportTraceServiceRequest with span_count
# equal to the count sent". Whether that sink is the in-process
# `StubSink` or the `ForwardingSink` to a downstream collector is
# orthogonal. Round-trip-to-downstream is E01's job.
#
# Verification:
#   1. telemetrygen exits 0 (proves aperture acked).
#   2. aperture's stderr shows `event=sink_accepted` for our exact
#      service.name with span_count == 2 (telemetrygen's default
#      generates a parent+child pair per trace, so --traces=1 yields
#      span_count=2).

set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

TELEMETRYGEN_IMAGE="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
SERVICE_NAME="expectation-A01-pilot"
EXPECTED_SPAN_COUNT=2

# 1. Wait for aperture readiness.
echo "step 1: waiting for aperture /readyz to return 200"
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

# 2. Send one OTLP/gRPC trace with a recognisable resource attribute.
echo "step 2: sending one OTLP/gRPC trace via telemetrygen"
docker run --rm --network "$COMPOSE_NETWORK" \
    "$TELEMETRYGEN_IMAGE" \
    traces \
        --otlp-endpoint=aperture:4317 \
        --otlp-insecure \
        --traces=1 \
        --otlp-attributes "service.name=\"${SERVICE_NAME}\"" \
    > "$EVIDENCE_DIR/telemetrygen.stdout.txt" \
    2> "$EVIDENCE_DIR/telemetrygen.stderr.txt"
echo "  telemetrygen exited 0"

# 3. Capture aperture's stderr at this moment so the assertion can see it.
sleep 1
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

# 4. Assert aperture observed the request and accepted it via its sink.
echo "step 3: checking aperture stderr for sink_accepted line"
ACCEPT_LINE="$(grep -F '"event":"sink_accepted"' "$EVIDENCE_DIR/aperture.live.stderr.txt" \
                 | grep -F "\"signal\":\"traces\"" \
                 | grep -F "\"resource.service.name\":\"${SERVICE_NAME}\"" || true)"

if [[ -z "$ACCEPT_LINE" ]]; then
    echo "no sink_accepted line for service ${SERVICE_NAME} traces in aperture stderr" >&2
    exit 1
fi
echo "  found: ${ACCEPT_LINE}"

# Extract span_count and assert it matches.
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

echo "OK — aperture acked the OTLP/gRPC request and emitted sink_accepted with matching span_count and service.name"
