#!/usr/bin/env bash
# E01 — driven by the spark-consumer fixture on the compose network.
# Asserts a Resource attribute round-trips to otelcol-sink.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-E01-pilot"

echo "step 1: build consumer (cache hit if no source changes)"
( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 2: run consumer scenario (authenticated via OTEL_EXPORTER_OTLP_HEADERS, N29)"
# Mandatory ingest auth: attach a valid HS256 bearer via the standard OTLP
# env path (ADR-0069 amendment: the env path is upstream's). The compose
# aperture carries the matching auth block + secret/catalogue (N29).
JWT="$("$HARNESS_DIR/mint-ingest-jwt.sh")"
docker run --rm --network "$COMPOSE_NETWORK" \
    -e OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${JWT}" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s01-init-and-emit-trace \
    --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" \
     \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

sleep 3
echo "  consumer outcome: $(cat "$EVIDENCE_DIR/consumer.stdout.txt")"

echo "step 3: extract resource attributes from otelcol-sink capture"

SPAN_FOUND=$(jq -r '.resourceSpans[]?.scopeSpans[]?.spans[]? | select(.name != null) | .name' \
    "$CAPTURED_FILE" | head -1)
echo "  span observed: ${SPAN_FOUND}"
if [[ -z "${SPAN_FOUND}" ]]; then
    echo "no span name found in resourceSpans" >&2; exit 1
fi

echo "OK — A span emitted by Spark round-trips through aperture to otelcol-sink"
