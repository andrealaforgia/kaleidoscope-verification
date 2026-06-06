#!/usr/bin/env bash
# K18 — an unknown item on `migrate`/`get-tier` fails closed (exit 1)
# AND the operator-facing diagnostic names the item cleanly as
# `unknown item "ghost"`, per UC-TIER-008 / UC-TIER-009.
#
# TRANSITION-PROOF: this asserts the DESIRED contract. As of the
# grounding SHA the binary leaks the internal newtype Debug form
# `unknown item ItemId("ghost")` instead of `"ghost"`, so the
# message assertion is RED while exit 1 already holds. It flips
# GREEN unchanged once the diagnostic drops the ItemId() wrapper.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" migrate acme /data ghost warm > /tmp/mig.out 2>&1
echo "mig-exit=$?" > /tmp/mig.rc
echo "---migrate ghost---"; cat /tmp/mig.rc; cat /tmp/mig.out
cp /tmp/mig.out "'"$EVIDENCE_DIR"'/migrate-ghost.out"; cp /tmp/mig.rc "'"$EVIDENCE_DIR"'/migrate-ghost.rc"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" get-tier acme /data ghost > /tmp/gt.out 2>&1
echo "gt-exit=$?" > /tmp/gt.rc
echo "---get-tier ghost---"; cat /tmp/gt.rc; cat /tmp/gt.out
cp /tmp/gt.out "'"$EVIDENCE_DIR"'/gettier-ghost.out"; cp /tmp/gt.rc "'"$EVIDENCE_DIR"'/gettier-ghost.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K18 "$INLINE"

# Fail-closed: exit 1 on both paths (already holds today).
grep -qx 'mig-exit=1' "$EVIDENCE_DIR/migrate-ghost.rc" || \
    { echo "migrate of unknown item did not exit 1" >&2; exit 1; }
grep -qx 'gt-exit=1' "$EVIDENCE_DIR/gettier-ghost.rc" || \
    { echo "get-tier of unknown item did not exit 1" >&2; exit 1; }
# Clean diagnostic: names the item as "ghost", not ItemId("ghost").
grep -qF 'unknown item "ghost"' "$EVIDENCE_DIR/migrate-ghost.out" || \
    { echo "migrate diagnostic does not name the item cleanly as \"ghost\" (UC-TIER-008)" >&2; exit 1; }
grep -qF 'unknown item "ghost"' "$EVIDENCE_DIR/gettier-ghost.out" || \
    { echo "get-tier diagnostic does not name the item cleanly as \"ghost\" (UC-TIER-009)" >&2; exit 1; }
echo "OK — unknown item fails closed with a clean \"ghost\" diagnostic"
