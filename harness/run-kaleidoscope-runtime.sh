#!/usr/bin/env bash
# run-kaleidoscope-runtime.sh — shared driver for CR-prefix runners.
#
# The consolidated-runtime binary (`kaleidoscope`, crate
# kaleidoscope-runtime, consolidated-runtime-v0/ADR-0076) is a real
# runnable service at HEAD but the project ships no Dockerfile for it.
# This driver injects the catalogue-authored
# harness/Dockerfile.kaleidoscope-runtime into the HEAD snapshot, builds
# the runtime image from the project's own workspace + Cargo.lock, then
# runs an inline scenario script.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label (filename stem for the scenario's stdout/stderr)
#   $3 = inline bash script. Available inside:
#         $CRT_IMAGE — the tagged image name
#         $DATA_HOST — host-side temp dir (a fresh, empty pillar root;
#                      bind-mount it at /data)

set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
INLINE_SCRIPT="$3"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CRT_IMAGE="kaleidoscope-expectations/kaleidoscope-runtime:under-test"

cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAPSHOT_DIR/Dockerfile.kaleidoscope-runtime"

echo "step 1: build kaleidoscope-runtime image (cache hit if no source change)" >&2
docker build \
    --quiet \
    -t "$CRT_IMAGE" \
    -f "$SNAPSHOT_DIR/Dockerfile.kaleidoscope-runtime" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t crt-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export CRT_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
