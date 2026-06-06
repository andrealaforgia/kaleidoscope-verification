#!/usr/bin/env bash
# K19 — tier literals are case-sensitive lowercase `hot`/`warm`/`cold`;
# anything else (upper-case `HOT`, unknown `archive`) is rejected with
# a non-zero exit and a clear diagnostic. Covers UC-TIER-010.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data item-1 HOT > /tmp/upper.out 2>&1
echo "upper-exit=$?" > /tmp/upper.rc
echo "---place HOT---"; cat /tmp/upper.rc; cat /tmp/upper.out
cp /tmp/upper.out "'"$EVIDENCE_DIR"'/place-HOT.out"; cp /tmp/upper.rc "'"$EVIDENCE_DIR"'/place-HOT.rc"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data item-1 archive > /tmp/arch.out 2>&1
echo "arch-exit=$?" > /tmp/arch.rc
echo "---place archive---"; cat /tmp/arch.rc; cat /tmp/arch.out
cp /tmp/arch.out "'"$EVIDENCE_DIR"'/place-archive.out"; cp /tmp/arch.rc "'"$EVIDENCE_DIR"'/place-archive.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K19 "$INLINE"

grep -qx 'upper-exit=0' "$EVIDENCE_DIR/place-HOT.rc" && \
    { echo "place accepted upper-case HOT (should be case-sensitive)" >&2; exit 1; }
grep -qF 'invalid tier "HOT": expected one of hot, warm, cold' "$EVIDENCE_DIR/place-HOT.out" || \
    { echo "missing the case-sensitive invalid-tier diagnostic for HOT" >&2; exit 1; }
grep -qx 'arch-exit=0' "$EVIDENCE_DIR/place-archive.rc" && \
    { echo "place accepted unknown literal archive" >&2; exit 1; }
grep -qF 'invalid tier "archive": expected one of hot, warm, cold' "$EVIDENCE_DIR/place-archive.out" || \
    { echo "missing the invalid-tier diagnostic for archive" >&2; exit 1; }
echo "OK — HOT and archive are both rejected with the invalid-tier diagnostic"
