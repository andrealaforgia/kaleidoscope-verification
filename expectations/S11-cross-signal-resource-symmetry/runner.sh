#!/usr/bin/env bash
# S11 — Traces, logs, metrics from the same Spark carry an identical
# Resource attribute set on each.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-S11-pilot"

( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

echo "step 1: run s11-cross-signal-symmetry scenario"
docker run --rm --network "$COMPOSE_NETWORK" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s11-cross-signal-symmetry \
    --service-name "$SERVICE_NAME" \
    --require-tenant-id --tenant-id acme-S11 \
    --endpoint "http://aperture:4317" \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

sleep 3

echo "step 2: extract Resource attribute sets per signal"
for SIGNAL in resourceSpans resourceLogs resourceMetrics; do
    jq -r ".${SIGNAL}[]?.resource.attributes[]? | \"\\(.key)=\\(.value.stringValue // .value.intValue // .value.boolValue)\"" \
        "$CAPTURED_FILE" | sort -u > "$EVIDENCE_DIR/resource.${SIGNAL}.txt"
    echo "  ${SIGNAL}: $(wc -l < "$EVIDENCE_DIR/resource.${SIGNAL}.txt") attribute(s)"
done

echo "step 3: diff resource sets"
diff "$EVIDENCE_DIR/resource.resourceSpans.txt" \
     "$EVIDENCE_DIR/resource.resourceLogs.txt" > "$EVIDENCE_DIR/diff.spans-vs-logs.txt" || {
    echo "Resource sets differ between traces and logs" >&2
    cat "$EVIDENCE_DIR/diff.spans-vs-logs.txt" >&2
    exit 1
}
diff "$EVIDENCE_DIR/resource.resourceSpans.txt" \
     "$EVIDENCE_DIR/resource.resourceMetrics.txt" > "$EVIDENCE_DIR/diff.spans-vs-metrics.txt" || {
    echo "Resource sets differ between traces and metrics" >&2
    cat "$EVIDENCE_DIR/diff.spans-vs-metrics.txt" >&2
    exit 1
}

echo "OK — Resource attribute sets identical across traces, logs, metrics"
