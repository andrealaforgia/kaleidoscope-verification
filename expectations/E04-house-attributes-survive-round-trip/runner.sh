#!/usr/bin/env bash
# E04 — driven by the spark-consumer fixture on the compose network.
# Asserts a Resource attribute round-trips to otelcol-sink.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-E04-pilot"

echo "step 1: build consumer (cache hit if no source changes)"
( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 2: run consumer scenario"
docker run --rm --network "$COMPOSE_NETWORK" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s01-init-and-emit-trace \
    --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" \
    --require-tenant-id --tenant-id acme-prod-E04 --feature-flag rollout=staged --experiment-id exp-E04-xyz \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

sleep 3
echo "  consumer outcome: $(cat "$EVIDENCE_DIR/consumer.stdout.txt")"

echo "step 3: extract resource attributes from otelcol-sink capture"

KEYS=$(jq -r '.resourceSpans[]?.resource.attributes[]? | .key' "$CAPTURED_FILE" | sort -u)
echo "  resource keys observed:"
echo "${KEYS}" | sed "s/^/    /"
for required in "service.name" "tenant.id" "feature_flag.rollout" "experiment.id"; do
    if ! echo "${KEYS}" | grep -qx "$required"; then
        echo "missing resource attribute: $required" >&2; exit 1
    fi
done

echo "OK — All four house attributes (service.name, tenant.id, feature_flag.*, experiment.id) survive the round-trip on Resource"
