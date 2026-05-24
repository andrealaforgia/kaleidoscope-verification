#!/usr/bin/env bash
# run-query-api.sh — shared driver for Q-prefix runners.
#
# Builds the query-api runtime image from the HEAD snapshot via
# the project-shipped Dockerfile.query-api at the workspace
# root, then runs an inline scenario script.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label (filename stem for the scenario's stdout/stderr)
#   $3 = inline bash script. Available inside:
#         $QAPI_IMAGE — the tagged image name
#         $DATA_HOST  — host-side temp dir (bind-mounted at /data
#                       in any `docker run` the script makes)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
QAPI_IMAGE="kaleidoscope-expectations/query-api:under-test"

echo "step 1: build query-api image (cache hit if no source change)" >&2
docker build \
    --quiet \
    -t "$QAPI_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.query-api" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t qapi-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export QAPI_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
