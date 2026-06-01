#!/usr/bin/env bash
# run-eg.sh — shared driver for EG-prefix runners (end-to-end via
# kaleidoscope-gateway plus query-api / log-query-api).
#
# Builds both runtime images from the HEAD snapshot, then runs an
# inline scenario script with both image tags + a host-side data
# dir available.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label
#   $3 = inline bash script. Available inside:
#         $GW_IMAGE   — kaleidoscope-gateway image tag
#         $QAPI_IMAGE — query-api image tag
#         $DATA_HOST  — host-side temp dir (use any /data mount
#                       layout the scenario needs)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
GW_IMAGE="kaleidoscope-expectations/kaleidoscope-gateway:under-test"
QAPI_IMAGE="kaleidoscope-expectations/query-api:under-test"
LQAPI_IMAGE="kaleidoscope-expectations/log-query-api:under-test"
TQAPI_IMAGE="kaleidoscope-expectations/trace-query-api:under-test"

echo "step 1a: build kaleidoscope-gateway image" >&2
docker build \
    --quiet \
    -t "$GW_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.gateway" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.gateway.build.txt" 2>&1

echo "step 1b: build query-api image" >&2
docker build \
    --quiet \
    -t "$QAPI_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.query-api" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.query-api.build.txt" 2>&1

# log-query-api: the project ships no Dockerfile, so inject the
# catalogue-authored one into the snapshot (see run-log-query-api.sh).
echo "step 1c: build log-query-api image" >&2
cp "$HARNESS_DIR/Dockerfile.log-query-api" "$SNAPSHOT_DIR/Dockerfile.log-query-api"
docker build \
    --quiet \
    -t "$LQAPI_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.log-query-api" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.log-query-api.build.txt" 2>&1

# trace-query-api: also project-unpackaged; inject the catalogue
# Dockerfile (see run-trace-query-api.sh). Cached after first build.
echo "step 1d: build trace-query-api image" >&2
cp "$HARNESS_DIR/Dockerfile.trace-query-api" "$SNAPSHOT_DIR/Dockerfile.trace-query-api"
docker build \
    --quiet \
    -t "$TQAPI_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.trace-query-api" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.trace-query-api.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t eg-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export GW_IMAGE QAPI_IMAGE LQAPI_IMAGE TQAPI_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
