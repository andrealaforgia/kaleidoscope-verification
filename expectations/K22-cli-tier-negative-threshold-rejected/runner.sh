#!/usr/bin/env bash
# K22 — evaluate-policy thresholds are non-negative integer seconds;
# a negative argument is rejected as a usage error rather than
# silently accepted or panicking. Covers UC-TIER-015.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" evaluate-policy /data -1 0 > /tmp/neg.out 2>&1
echo "neg-exit=$?" > /tmp/neg.rc
echo "---evaluate-policy -1 0---"; cat /tmp/neg.rc; cat /tmp/neg.out
cp /tmp/neg.out "'"$EVIDENCE_DIR"'/negative.out"; cp /tmp/neg.rc "'"$EVIDENCE_DIR"'/negative.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K22 "$INLINE"

grep -qx 'neg-exit=0' "$EVIDENCE_DIR/negative.rc" && \
    { echo "negative threshold was accepted (should be a usage error)" >&2; exit 1; }
grep -qx 'neg-exit=2' "$EVIDENCE_DIR/negative.rc" || \
    { echo "negative threshold did not exit with the usage code 2" >&2; exit 1; }
grep -qF 'Usage:' "$EVIDENCE_DIR/negative.out" || \
    { echo "negative threshold did not surface a usage diagnostic" >&2; exit 1; }
echo "OK — a negative threshold is rejected as a usage error (exit 2)"
