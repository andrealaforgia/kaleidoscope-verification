#!/usr/bin/env bash
# run-log-query-api.sh — shared driver for LQ-prefix runners.
#
# log-query-api is a real runnable service at HEAD (crates/
# log-query-api/src/main.rs binds an axum listener), but the
# kaleidoscope project ships no Dockerfile for it. This driver
# injects the catalogue-authored harness/Dockerfile.log-query-api
# into the HEAD snapshot, builds the runtime image from the project's
# own workspace + Cargo.lock, then runs an inline scenario script.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label (filename stem for the scenario's stdout/stderr)
#   $3 = inline bash script. Available inside:
#         $LQAPI_IMAGE — the tagged image name
#         $DATA_HOST   — host-side temp dir (a fresh, empty Lumen
#                        pillar root; bind-mount it at /data)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
LQAPI_IMAGE="kaleidoscope-expectations/log-query-api:under-test"

# Inject the catalogue-authored Dockerfile into the project snapshot.
# The snapshot is `git archive HEAD` of kaleidoscope and carries the
# workspace + Cargo.lock but not this file (the project ships none).
cp "$HARNESS_DIR/Dockerfile.log-query-api" "$SNAPSHOT_DIR/Dockerfile.log-query-api"

echo "step 1: build log-query-api image (cache hit if no source change)" >&2
docker build \
    --quiet \
    -t "$LQAPI_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.log-query-api" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t lqapi-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export LQAPI_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
