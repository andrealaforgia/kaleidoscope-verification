#!/usr/bin/env bash
# run-gateway.sh — shared driver for G-prefix runners.
#
# Builds the kaleidoscope-gateway runtime image from the HEAD
# snapshot via the project-shipped Dockerfile.gateway at the
# workspace root, then runs an inline scenario script.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label (filename stem for the scenario's stdout/stderr)
#   $3 = inline bash script. Available inside:
#         $GW_IMAGE   — the tagged image name
#         $DATA_HOST  — host-side temp dir (bind-mounted at /data
#                       in any `docker run` the script makes)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
GW_IMAGE="kaleidoscope-expectations/kaleidoscope-gateway:under-test"

echo "step 1: build kaleidoscope-gateway image (cache hit if no source change)" >&2
docker build \
    --quiet \
    -t "$GW_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.gateway" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t gw-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export GW_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
