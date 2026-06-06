#!/usr/bin/env bash
# E02 — A tracing::info!(target="<app>", ...) emitted from a
# Spark-instrumented app reaches Aperture as an OTLP LogRecord.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-E02-pilot"

( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 1: run e02-emit-log scenario"
# Mandatory ingest auth (N29): authenticate via the standard OTLP env path.
JWT="$("$HARNESS_DIR/mint-ingest-jwt.sh")"
docker run --rm --network "$COMPOSE_NETWORK" \
    -e OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${JWT}" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario e02-emit-log \
    --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

sleep 3

echo "step 2: look for resourceLogs in captured file"
LOGS_LINES=$(grep -c '"resourceLogs"' "$CAPTURED_FILE" || echo 0)
echo "  resourceLogs payload lines: ${LOGS_LINES}"
if (( LOGS_LINES == 0 )); then
    echo "no resourceLogs found in captured file" >&2
    exit 1
fi

OBSERVED_SVC=$(jq -r '.resourceLogs[]?.resource.attributes[]? | select(.key == "service.name") | .value.stringValue' \
    "$CAPTURED_FILE" | sort -u | head -1)
echo "  service.name on resourceLogs: ${OBSERVED_SVC}"
if [[ "$OBSERVED_SVC" != "$SERVICE_NAME" ]]; then
    echo "service.name mismatch on resourceLogs: got '${OBSERVED_SVC}', expected '${SERVICE_NAME}'" >&2
    exit 1
fi

echo "OK — tracing::info from Spark-instrumented app reaches otelcol-sink as resourceLogs"
