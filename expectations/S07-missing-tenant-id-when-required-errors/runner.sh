#!/usr/bin/env bash
# S07 — driven by the spark-consumer fixture, scenario
# `s07-missing-tenant-id`. Init-side check only, no aperture required.
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

echo "step 2: run scenario s07-missing-tenant-id"
docker run --rm \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s07-missing-tenant-id \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

echo "  consumer stdout:"
sed 's/^/    /' "$EVIDENCE_DIR/consumer.stdout.txt"

if ! grep -qE '^scenario=s07-missing-tenant-id result=ok detail=MissingRequiredAttribute name=tenant\.id$' "$EVIDENCE_DIR/consumer.stdout.txt"; then
    echo "consumer outcome line did not match expected pattern" >&2
    exit 1
fi

echo "OK — spark::init returned MissingRequiredAttribute(tenant.id) when require_tenant_id without with_tenant_id"
