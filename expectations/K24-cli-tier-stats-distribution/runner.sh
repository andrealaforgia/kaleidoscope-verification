#!/usr/bin/env bash
# K24 — `stats` reflects a known hot/warm/cold placement mix with
# matching per-tier counts. Covers UC-TIER-017 (extends K09, which
# only pinned the hot= line, to the full distribution). Place a
# 2-hot / 1-warm / 1-cold mix directly via `place`, then read stats.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data h1 hot  >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data h2 hot  >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data w1 warm >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data c1 cold >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" stats acme /data > /tmp/stats.out 2>&1
echo "---stats---"; cat /tmp/stats.out
cp /tmp/stats.out "'"$EVIDENCE_DIR"'/stats.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K24 "$INLINE"

grep -qx 'hot=2'  "$EVIDENCE_DIR/stats.out" || { echo "stats hot= count does not match the placed mix" >&2; exit 1; }
grep -qx 'warm=1' "$EVIDENCE_DIR/stats.out" || { echo "stats warm= count does not match the placed mix" >&2; exit 1; }
grep -qx 'cold=1' "$EVIDENCE_DIR/stats.out" || { echo "stats cold= count does not match the placed mix" >&2; exit 1; }
echo "OK — stats reports hot=2 warm=1 cold=1 matching the placed distribution"
