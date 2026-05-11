#!/usr/bin/env bash
# S06 — Without service.name, spark::init returns
# `Err(SparkError::MissingRequiredAttribute { name: "service.name" })`.
#
# Init-side check only. No OTLP traffic, no aperture required.
# Driven by the spark-consumer fixture (harness/spark-consumer/)
# which exposes a `--scenario s06-missing-service-name` mode that
# calls `SparkConfig::for_service("")` and inspects the returned
# error variant.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
export KALEIDOSCOPE_DIR="$SNAPSHOT_DIR"

# Ensure the spark-consumer image is built (idempotent: cache hits
# if the consumer source and the kaleidoscope snapshot haven't
# changed).
echo "step 1: ensure spark-consumer image is built"
( cd "$HARNESS_DIR" \
    && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1
echo "  spark-consumer image ready"

# Run the scenario as a one-shot container, no compose network needed.
echo "step 2: run scenario s06-missing-service-name"
docker run --rm \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s06-missing-service-name \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

echo "  consumer stdout:"
sed 's/^/    /' "$EVIDENCE_DIR/consumer.stdout.txt"

# Assert: a single line of shape
#   scenario=s06-missing-service-name result=ok detail=MissingRequiredAttribute name=service.name
if ! grep -qE '^scenario=s06-missing-service-name result=ok detail=MissingRequiredAttribute name=service.name$' \
        "$EVIDENCE_DIR/consumer.stdout.txt"; then
    echo "consumer outcome line did not match expected pattern" >&2
    exit 1
fi

echo "OK — spark::init returned MissingRequiredAttribute(service.name) on empty service name"
