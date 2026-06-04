#!/usr/bin/env bash
# run-crash-target.sh — shared driver for D-prefix durability runners
# that exercise a per-store `<store>-crash-target` binary built from the
# HEAD snapshot.
#
# Builds the runtime image (cache hit if no source change) and then runs
# an inline scenario script that drives the crash-target binary.
#
# Args:
#   $1 = EVIDENCE_DIR
#   $2 = label (filename stem for build/stdout/stderr)
#   $3 = CRATE (e.g. lumen)
#   $4 = BIN   (e.g. lumen-crash-target)
#   $5 = inline bash script. Available inside:
#         $CT_IMAGE   — the tagged image name (ENTRYPOINT = the binary)
#         $DATA_HOST  — host-side temp dir to bind-mount at /data
set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
CRATE="$3"
BIN="$4"
INLINE_SCRIPT="$5"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CT_IMAGE="kaleidoscope-expectations/${BIN}:under-test"

echo "step 1: build ${BIN} image (cache hit if no source change)" >&2
docker build \
    --quiet \
    --build-arg CRATE="$CRATE" \
    --build-arg BIN="$BIN" \
    -t "$CT_IMAGE" \
    -f "$HARNESS_DIR/Dockerfile.crash-target" \
    "$SNAPSHOT_DIR" \
    > "$EVIDENCE_DIR/${LABEL}.build.txt" 2>&1

DATA_HOST=$(mktemp -d -t ct-${LABEL}-XXXXXX)
trap "rm -rf '$DATA_HOST'" EXIT

export CT_IMAGE DATA_HOST
bash -c "$INLINE_SCRIPT" \
    > "$EVIDENCE_DIR/${LABEL}.stdout.txt" \
    2> "$EVIDENCE_DIR/${LABEL}.stderr.txt"
