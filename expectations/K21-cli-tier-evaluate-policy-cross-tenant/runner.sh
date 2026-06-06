#!/usr/bin/env bash
# K21 — `evaluate-policy` takes no tenant positional and ages items
# across ALL tenants in a single call. Covers UC-TIER-013. Place a
# hot item under two distinct tenants, run one evaluate-policy, and
# confirm both tenants' items advanced.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme   /data item-1 hot >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place globex /data item-2 hot >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" evaluate-policy /data 0 0 > /tmp/ev.out 2>&1
echo "---evaluate (cross-tenant)---"; cat /tmp/ev.out; cp /tmp/ev.out "'"$EVIDENCE_DIR"'/evaluate.out"
{ echo -n "acme item-1: ";   docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme   /data item-1
  echo -n "globex item-2: "; docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier globex /data item-2; } > /tmp/tiers.out 2>&1
echo "---tiers after---"; cat /tmp/tiers.out; cp /tmp/tiers.out "'"$EVIDENCE_DIR"'/tiers-after.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K21 "$INLINE"

grep -qx 'evaluated migrated=2' "$EVIDENCE_DIR/evaluate.out" || \
    { echo "single evaluate-policy did not age both tenants' items" >&2; exit 1; }
grep -qx 'acme item-1: tier=warm' "$EVIDENCE_DIR/tiers-after.out" || \
    { echo "acme's item was not aged by the cross-tenant call" >&2; exit 1; }
grep -qx 'globex item-2: tier=warm' "$EVIDENCE_DIR/tiers-after.out" || \
    { echo "globex's item was not aged by the cross-tenant call" >&2; exit 1; }
echo "OK — one tenant-less evaluate-policy ages items across both tenants"
