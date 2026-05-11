#!/usr/bin/env bash
# S09 — driven by the spark-consumer fixture, scenario
# `s09-double-init`. Init-side check only, no aperture required.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
export KALEIDOSCOPE_DIR="$SNAPSHOT_DIR"

echo "step 1: ensure spark-consumer image is built"
( cd "$HARNESS_DIR" \
    && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1
echo "  spark-consumer image ready"

echo "step 2: run scenario s09-double-init"
docker run --rm \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s09-double-init \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

echo "  consumer stdout:"
sed 's/^/    /' "$EVIDENCE_DIR/consumer.stdout.txt"

if ! grep -qE '^scenario=s09-double-init result=ok detail=second init returned GlobalAlreadyInitialised$' "$EVIDENCE_DIR/consumer.stdout.txt"; then
    echo "consumer outcome line did not match expected pattern" >&2
    exit 1
fi

echo "OK — second spark::init while first guard alive returns GlobalAlreadyInitialised"
