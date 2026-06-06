#!/usr/bin/env bash
# K14 — `place` reports the placement and `get-tier` reads it back.
# Covers UC-TIER-001 (place an item in a tier) and UC-TIER-002
# (get an item's tier). The get-tier runs in a SEPARATE container
# against the same volume, so a pass also demonstrates UC-TIER-016
# (placement survives a fresh process reading the same data dir).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data item-1 hot > /tmp/place.out 2>&1
echo "---place---"; cat /tmp/place.out
cp /tmp/place.out "'"$EVIDENCE_DIR"'/place.out"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-1 > /tmp/gettier.out 2>&1
echo "---get-tier---"; cat /tmp/gettier.out
cp /tmp/gettier.out "'"$EVIDENCE_DIR"'/gettier.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K14 "$INLINE"

grep -qx 'placed tenant=acme item=item-1 tier=hot' "$EVIDENCE_DIR/place.out" || \
    { echo "place did not report the expected placement line" >&2; exit 1; }
grep -qx 'tier=hot' "$EVIDENCE_DIR/gettier.out" || \
    { echo "get-tier did not read back tier=hot from a fresh container" >&2; exit 1; }
echo "OK — place reports placement; a fresh get-tier reads back tier=hot"
