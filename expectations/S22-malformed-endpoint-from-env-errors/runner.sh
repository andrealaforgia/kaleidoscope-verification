#!/usr/bin/env bash
# S22 — Malformed endpoint from OTEL_EXPORTER_OTLP_ENDPOINT env var
# returns Err(InvalidEndpoint).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
export KALEIDOSCOPE_DIR="$HARNESS_DIR/.snapshot"

echo "step 1: build consumer"
( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 2: run scenario with malformed OTEL_EXPORTER_OTLP_ENDPOINT"
docker run --rm \
    -e OTEL_EXPORTER_OTLP_ENDPOINT='this-is-not-a-valid-url' \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s22-malformed-endpoint-from-env \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

echo "  consumer stdout: $(cat "$EVIDENCE_DIR/consumer.stdout.txt")"

if ! grep -qE '^scenario=s22-malformed-endpoint-from-env result=ok detail=InvalidEndpoint' \
        "$EVIDENCE_DIR/consumer.stdout.txt"; then
    echo "consumer outcome line did not match expected pattern" >&2
    exit 1
fi

echo "OK — malformed endpoint from env var → InvalidEndpoint"
