#!/usr/bin/env bash
# K20 — `evaluate-policy` ages items one tier-step per pass: with
# zero thresholds, freshly-placed hot items move hot->warm on the
# first evaluation and warm->cold on the second. Covers UC-TIER-011
# (hot->warm), UC-TIER-012 (warm->cold) and UC-TIER-014 (zero
# thresholds well-defined: everything eligible moves).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
for it in item-1 item-2; do
  docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data "$it" hot >/dev/null 2>&1
done
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" evaluate-policy /data 0 0 > /tmp/ev1.out 2>&1
echo "---evaluate #1---"; cat /tmp/ev1.out; cp /tmp/ev1.out "'"$EVIDENCE_DIR"'/evaluate-1.out"
{ docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-1
  docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-2; } > /tmp/after1.out 2>&1
echo "---tiers after #1---"; cat /tmp/after1.out; cp /tmp/after1.out "'"$EVIDENCE_DIR"'/tiers-after-1.out"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" evaluate-policy /data 0 0 > /tmp/ev2.out 2>&1
echo "---evaluate #2---"; cat /tmp/ev2.out; cp /tmp/ev2.out "'"$EVIDENCE_DIR"'/evaluate-2.out"
{ docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-1
  docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data item-2; } > /tmp/after2.out 2>&1
echo "---tiers after #2---"; cat /tmp/after2.out; cp /tmp/after2.out "'"$EVIDENCE_DIR"'/tiers-after-2.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K20 "$INLINE"

grep -qx 'evaluated migrated=2' "$EVIDENCE_DIR/evaluate-1.out" || \
    { echo "first evaluate-policy did not migrate the 2 hot items" >&2; exit 1; }
grep -qx 'tier=warm' "$EVIDENCE_DIR/tiers-after-1.out" && \
    [[ $(grep -c '^tier=warm$' "$EVIDENCE_DIR/tiers-after-1.out") -eq 2 ]] || \
    { echo "after pass #1 both items should be warm (hot->warm)" >&2; exit 1; }
grep -qx 'evaluated migrated=2' "$EVIDENCE_DIR/evaluate-2.out" || \
    { echo "second evaluate-policy did not migrate the 2 warm items" >&2; exit 1; }
[[ $(grep -c '^tier=cold$' "$EVIDENCE_DIR/tiers-after-2.out") -eq 2 ]] || \
    { echo "after pass #2 both items should be cold (warm->cold)" >&2; exit 1; }
echo "OK — evaluate-policy ages hot->warm then warm->cold, one step per pass"
