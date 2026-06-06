#!/usr/bin/env bash
# K23 — tier state is per-tenant: the same item id placed in
# different tiers under two tenants does not bleed across the tenant
# boundary on list-items or get-tier. Covers UC-TIER-018.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme   /data item-x hot  >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place globex /data item-x cold >/dev/null 2>&1
{
  echo -n "acme-hot: ";    docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items acme   /data hot  | tr "\n" ","
  echo
  echo -n "acme-cold: ";   docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items acme   /data cold | tr "\n" ","
  echo
  echo -n "globex-cold: "; docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items globex /data cold | tr "\n" ","
  echo
  echo -n "globex-hot: ";  docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items globex /data hot  | tr "\n" ","
  echo
  echo -n "acme tier: ";   docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme   /data item-x
  echo -n "globex tier: "; docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier globex /data item-x
} > /tmp/iso.out 2>&1
echo "---isolation view---"; cat /tmp/iso.out
cp /tmp/iso.out "'"$EVIDENCE_DIR"'/isolation.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K23 "$INLINE"

F="$EVIDENCE_DIR/isolation.out"
grep -qx 'acme-hot: item-x,'    "$F" || { echo "acme hot should list item-x" >&2; exit 1; }
grep -qx 'acme-cold: '          "$F" || { echo "acme cold should be empty (no bleed from globex)" >&2; exit 1; }
grep -qx 'globex-cold: item-x,' "$F" || { echo "globex cold should list item-x" >&2; exit 1; }
grep -qx 'globex-hot: '         "$F" || { echo "globex hot should be empty (no bleed from acme)" >&2; exit 1; }
grep -qx 'acme tier: tier=hot'    "$F" || { echo "acme item-x should be hot" >&2; exit 1; }
grep -qx 'globex tier: tier=cold' "$F" || { echo "globex item-x should be cold" >&2; exit 1; }
echo "OK — identical item id under two tenants keeps independent tier state"
