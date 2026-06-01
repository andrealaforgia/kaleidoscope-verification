#!/usr/bin/env bash
# run-trace-query-api.sh — shared driver for TQ-prefix runners.
#
# trace-query-api is a real runnable service at HEAD (crates/
# trace-query-api/src/main.rs binds an axum listener on :9092), but
# the kaleidoscope project ships no Dockerfile for it. This driver
# injects the catalogue-authored harness/Dockerfile.trace-query-api
# into the HEAD snapshot, builds the runtime image from the project's
# own workspace + Cargo.lock, then runs an inline scenario script.
# Same recipe the LQ-prefix uses for log-query-api.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label
#   $3 = inline bash script. Available inside:
#         $TQAPI_IMAGE — the tagged image name
#         $DATA_HOST   — a fresh, empty Ray pillar root (bind at /data)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
TQAPI_IMAGE="kaleidoscope-expectations/trace-query-api:under-test"

cp "$HARNESS_DIR/Dockerfile.trace-query-api" "$SNAPSHOT_DIR/Dockerfile.trace-query-api"

echo "step 1: build trace-query-api image (cache hit if no source change)" >&2
docker build \
    --quiet \
    -t "$TQAPI_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.trace-query-api" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t tqapi-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export TQAPI_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
