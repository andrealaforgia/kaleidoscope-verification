#!/usr/bin/env bash
# S02 — driven by the spark-consumer fixture on the compose network.
# Asserts a Resource attribute round-trips to otelcol-sink.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-S02-pilot"

echo "step 1: build consumer (cache hit if no source changes)"
( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 2: run consumer scenario"
docker run --rm --network "$COMPOSE_NETWORK" \
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

OBSERVED=$(jq -r '.resourceSpans[]?.resource.attributes[]? | select(.key == "service.name") | .value.stringValue' \
    "$CAPTURED_FILE" | sort -u | grep "$SERVICE_NAME" || true)
echo "  service.name observed: ${OBSERVED}"
if [[ "$OBSERVED" != "$SERVICE_NAME" ]]; then
    echo "expected resource.service.name=$SERVICE_NAME, got ${OBSERVED}" >&2
    exit 1
fi

echo "OK — Resource carries service.name exactly as set on SparkConfig::for_service"
