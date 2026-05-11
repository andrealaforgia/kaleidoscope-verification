#!/usr/bin/env bash
# S04 — driven by the spark-consumer fixture on the compose network.
# Asserts a Resource attribute round-trips to otelcol-sink.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-S04-pilot"

echo "step 1: build consumer (cache hit if no source changes)"
( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 2: run consumer scenario"
docker run --rm --network "$COMPOSE_NETWORK" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s01-init-and-emit-trace \
    --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" \
    --feature-flag rollout=canary --feature-flag region=eu \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

sleep 3
echo "  consumer outcome: $(cat "$EVIDENCE_DIR/consumer.stdout.txt")"

echo "step 3: extract resource attributes from otelcol-sink capture"

OBSERVED=$(jq -r '.resourceSpans[]?.resource.attributes[]? | select(.key | startswith("feature_flag.")) | "\(.key)=\(.value.stringValue)"' \
    "$CAPTURED_FILE" | sort -u)
echo "  feature_flag.* observed:"
echo "${OBSERVED}" | sed "s/^/    /"
if ! echo "${OBSERVED}" | grep -q "feature_flag.rollout=canary"; then
    echo "missing feature_flag.rollout=canary" >&2; exit 1
fi
if ! echo "${OBSERVED}" | grep -q "feature_flag.region=eu"; then
    echo "missing feature_flag.region=eu" >&2; exit 1
fi

echo "OK — Resource carries feature_flag.{key} attributes from with_feature_flags"
