#!/usr/bin/env bash
# K15 — `migrate` reports the move and the new tier persists for a
# fresh `get-tier` reader. Covers UC-TIER-003 (migrate between tiers)
# and UC-TIER-004 (migrate updates the persisted tier).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data item-1 hot >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" migrate acme /data item-1 warm > /tmp/migrate.out 2>&1
echo "---migrate---"; cat /tmp/migrate.out
cp /tmp/migrate.out "'"$EVIDENCE_DIR"'/migrate.out"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-1 > /tmp/gettier.out 2>&1
echo "---get-tier---"; cat /tmp/gettier.out
cp /tmp/gettier.out "'"$EVIDENCE_DIR"'/gettier.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K15 "$INLINE"

grep -qx 'migrated tenant=acme item=item-1 from=hot to=warm' "$EVIDENCE_DIR/migrate.out" || \
    { echo "migrate did not report the expected from/to line" >&2; exit 1; }
grep -qx 'tier=warm' "$EVIDENCE_DIR/gettier.out" || \
    { echo "migrated tier did not persist to a fresh get-tier" >&2; exit 1; }
echo "OK — migrate reports hot->warm; the new tier persists across a fresh reader"
