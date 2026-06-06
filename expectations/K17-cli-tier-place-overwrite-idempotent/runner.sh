#!/usr/bin/env bash
# K17 — re-placing an existing item updates its tier without error
# (overwrite semantics). Covers UC-TIER-007. Place hot, then place
# the same id cold; the second place succeeds and get-tier reads cold.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data item-1 hot >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data item-1 cold > /tmp/place2.out 2>&1
echo "place2-exit=$?" > /tmp/place2.rc
echo "---second place---"; cat /tmp/place2.out; cat /tmp/place2.rc
cp /tmp/place2.out "'"$EVIDENCE_DIR"'/place2.out"
cp /tmp/place2.rc "'"$EVIDENCE_DIR"'/place2.rc"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-1 > /tmp/gettier.out 2>&1
echo "---get-tier---"; cat /tmp/gettier.out
cp /tmp/gettier.out "'"$EVIDENCE_DIR"'/gettier.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K17 "$INLINE"

grep -qx 'place2-exit=0' "$EVIDENCE_DIR/place2.rc" || \
    { echo "re-place did not succeed (overwrite should not error)" >&2; exit 1; }
grep -qx 'placed tenant=acme item=item-1 tier=cold' "$EVIDENCE_DIR/place2.out" || \
    { echo "re-place did not report the new tier" >&2; exit 1; }
grep -qx 'tier=cold' "$EVIDENCE_DIR/gettier.out" || \
    { echo "overwrite did not take effect (tier not cold)" >&2; exit 1; }
echo "OK — re-place overwrites the tier idempotently, no error"
