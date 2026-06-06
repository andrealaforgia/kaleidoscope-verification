#!/usr/bin/env bash
# K16 — `list-items` prints one ItemId per line, lexicographically
# sorted regardless of placement order, and an empty tier prints
# nothing with exit 0. Covers UC-TIER-005 (list items in a tier) and
# UC-TIER-006 (list an empty tier).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
# Place out of lexical order on purpose.
for it in item-b item-a item-c; do
  docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" place acme /data "$it" hot >/dev/null 2>&1
done
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items acme /data hot > /tmp/list-hot.out 2>&1
echo "---list hot---"; cat /tmp/list-hot.out
cp /tmp/list-hot.out "'"$EVIDENCE_DIR"'/list-hot.out"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items acme /data cold > /tmp/list-cold.out 2>&1
echo "list-cold-exit=$?" > /tmp/list-cold.rc
echo "---list cold (rc)---"; cat /tmp/list-cold.rc; echo "[contents below]"; cat /tmp/list-cold.out
cp /tmp/list-cold.out "'"$EVIDENCE_DIR"'/list-cold.out"
cp /tmp/list-cold.rc "'"$EVIDENCE_DIR"'/list-cold.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K16 "$INLINE"

printf 'item-a\nitem-b\nitem-c\n' > "$EVIDENCE_DIR/expected-hot.txt"
diff -u "$EVIDENCE_DIR/expected-hot.txt" "$EVIDENCE_DIR/list-hot.out" || \
    { echo "list-items hot is not the lex-sorted item set" >&2; exit 1; }
[[ -s "$EVIDENCE_DIR/list-cold.out" ]] && \
    { echo "list-items cold should be empty but had content" >&2; exit 1; }
grep -qx 'list-cold-exit=0' "$EVIDENCE_DIR/list-cold.rc" || \
    { echo "list-items on an empty tier did not exit 0" >&2; exit 1; }
echo "OK — list-items is lex-sorted; empty tier prints nothing, exit 0"
