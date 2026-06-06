#!/usr/bin/env bash
# E03 — A counter incremented from a Spark-instrumented app reaches
# Aperture as an OTLP MetricsRequest after flush.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-E03-pilot"

( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 1: run e03-emit-metric scenario"
# Mandatory ingest auth (N29): authenticate via the standard OTLP env path.
JWT="$("$HARNESS_DIR/mint-ingest-jwt.sh")"
docker run --rm --network "$COMPOSE_NETWORK" \
    -e OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${JWT}" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario e03-emit-metric \
    --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

sleep 3

echo "step 2: look for resourceMetrics in captured file"
METRICS_LINES=$(grep -c '"resourceMetrics"' "$CAPTURED_FILE" || echo 0)
echo "  resourceMetrics payload lines: ${METRICS_LINES}"
if (( METRICS_LINES == 0 )); then
    echo "no resourceMetrics found in captured file" >&2
    exit 1
fi

OBSERVED_SVC=$(jq -r '.resourceMetrics[]?.resource.attributes[]? | select(.key == "service.name") | .value.stringValue' \
    "$CAPTURED_FILE" | sort -u | head -1)
echo "  service.name on resourceMetrics: ${OBSERVED_SVC}"
if [[ "$OBSERVED_SVC" != "$SERVICE_NAME" ]]; then
    echo "service.name mismatch on resourceMetrics" >&2
    exit 1
fi

echo "OK — counter add() from Spark-instrumented app reaches otelcol-sink as resourceMetrics"
