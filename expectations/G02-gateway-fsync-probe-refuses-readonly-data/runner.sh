#!/usr/bin/env bash
# G02 — `kaleidoscope-gateway` started with a READ-ONLY pillar
# root refuses to bind: the fsync-honesty probe (ADR-0049,
# commit 5ccf4a9) writes a sentinel and fsyncs it; with /data
# mounted :ro the write fails and the binary exits non-zero
# before any listener binds. Anchors the new Earned-Trust
# fsync contract introduced by `feat(earned-trust): honour
# fsync at pulse write path and gateway startup`.
#
# Note: gateway's `tracing::error!(event="health.startup.refused")`
# is dropped because main.rs installs no tracing subscriber
# pre-spawn (issue 005). The operator-visible signal is the
# `Err(...)` from default main + a non-zero exit code.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="g02-$$"
EC=0
# Mount /data read-only so the fsync probe is forced to fail.
docker run --rm \
    --name "$NAME" \
    -v "$DATA_HOST:/data:ro" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    "$GW_IMAGE" > /tmp/gw.out 2> /tmp/gw.err || EC=$?
echo "exit=$EC"
echo "---stderr (first 30 lines)---"
head -30 /tmp/gw.err
cp /tmp/gw.err "'"$EVIDENCE_DIR"'/gateway.stderr.txt"
cp /tmp/gw.out "'"$EVIDENCE_DIR"'/gateway.stdout.txt"
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G02 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/G02.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" != "0" ]] || { echo "expected non-zero exit (read-only data should fail fsync probe); got $EC" >&2; exit 1; }
# The default Result-from-main print path should mention fsync,
# read-only, or the substrate descriptor. Match loosely (issue
# 005 means the structured `health.startup.refused` event is
# dropped; what reaches stderr is the Err(...) inner).
grep -qiE "fsync|read-only|readonly|read.only|substrate|storage.sink.*prob|startup.refused" \
    "$EVIDENCE_DIR/gateway.stderr.txt" || {
    echo "stderr lacks any fsync/read-only/substrate diagnostic" >&2
    head -30 "$EVIDENCE_DIR/gateway.stderr.txt" >&2
    exit 1
}
echo "OK — gateway refuses startup with read-only /data: exit=${EC} + fsync/readonly diagnostic on stderr"
