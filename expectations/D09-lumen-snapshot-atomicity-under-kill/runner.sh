#!/usr/bin/env bash
# D09 — lumen SNAPSHOT ATOMICITY under a mid-snapshot process kill
# (black-box, on-disk).
#
# store-fsync-durability-v0 writes each snapshot atomically (ADR-0060 §2):
# serialise to `{canonical}.tmp` in the same directory, fsync the tmp,
# rename onto the canonical path, fsync the parent dir. A crash at ANY
# instant must therefore leave the CANONICAL snapshot path whole-or-absent
# (never a torn/half-written file), and the acked datum must remain
# recoverable from durable on-disk state (the WAL until the first
# snapshot, the snapshot thereafter; the rename-before-truncate ordering
# means at least one always holds it whole).
#
# The implementer shipped `lumen-crash-target --seed-then-loop-snapshot`
# to surface this out-of-process: it ingests one acked record, prints
# CRASH_TARGET_READY only AFTER that record is durable, then loops writing
# snapshots so a SIGKILL lands mid-snapshot.
#
# Given a seeded, acked record and the crash-target looping snapshots
# When the process is SIGKILLed mid-snapshot and the data dir inspected
# Then the canonical `store.snapshot` is whole (parses) or absent, never
#      torn; and the acked record is present in durable on-disk state
#      (WAL or snapshot).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

BODY="d09-acked-kal"
INLINE='
NAME="d09-crash-$$"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# Loop snapshots forever; SIGKILL must land while one is in flight.
docker run -d --name "$NAME" \
    -e KALEIDOSCOPE_CRASH_PILLAR_ROOT=/data \
    -v "$DATA_HOST:/data" \
    "$CT_IMAGE" --seed-then-loop-snapshot --body "'"$BODY"'" >/dev/null

# Wait for the readiness sentinel (emitted only after the acked record is
# durable), then let the snapshot loop run briefly so a kill lands in it.
READY=no
for _ in $(seq 1 100); do
    if docker logs "$NAME" 2>/dev/null | grep -q CRASH_TARGET_READY; then READY=yes; break; fi
    sleep 0.1
done
echo "ready=$READY"
sleep 0.3
# Capture whether a mid-flight tmp exists at the instant of the kill.
TMP_AT_KILL=no; [[ -f "$DATA_HOST/store.snapshot.tmp" ]] && TMP_AT_KILL=yes
echo "tmp_at_kill=$TMP_AT_KILL"
docker kill -s KILL "$NAME" >/dev/null 2>&1 || true
docker logs "$NAME" > /tmp/d09.logs 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Freeze the on-disk state as evidence.
ls -laR "$DATA_HOST" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
cp "$DATA_HOST/store.snapshot" "'"$EVIDENCE_DIR"'/store.snapshot" 2>/dev/null || echo "(no canonical snapshot)" > "'"$EVIDENCE_DIR"'/store.snapshot"
cp "$DATA_HOST/store.wal" "'"$EVIDENCE_DIR"'/store.wal" 2>/dev/null || echo "(no wal)" > "'"$EVIDENCE_DIR"'/store.wal"
cp /tmp/d09.logs "'"$EVIDENCE_DIR"'/crash-target.logs" 2>/dev/null || true

SNAP_PRESENT=no; [[ -f "$DATA_HOST/store.snapshot" ]] && SNAP_PRESENT=yes
echo "snapshot_present=$SNAP_PRESENT"

# Canonical snapshot, if present, must be WHOLE (parse as JSON). A torn
# canonical file is the exact defect atomic-write forbids.
SNAP_WHOLE=na
if [[ "$SNAP_PRESENT" == yes ]]; then
    if jq -e . "$DATA_HOST/store.snapshot" >/dev/null 2>&1; then SNAP_WHOLE=yes; else SNAP_WHOLE=no; fi
fi
echo "snapshot_whole=$SNAP_WHOLE"

# Acked datum present in durable on-disk state: snapshot OR WAL.
IN_SNAP=no
[[ "$SNAP_WHOLE" == yes ]] && jq -e --arg b "'"$BODY"'" "[.. | .body? // empty] | any(. == \$b)" "$DATA_HOST/store.snapshot" >/dev/null 2>&1 && IN_SNAP=yes
IN_WAL=no
if [[ -f "$DATA_HOST/store.wal" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if printf "%s" "$line" | jq -e --arg b "'"$BODY"'" ".body == \$b" >/dev/null 2>&1; then IN_WAL=yes; break; fi
    done < "$DATA_HOST/store.wal"
fi
echo "acked_in_snapshot=$IN_SNAP"
echo "acked_in_wal=$IN_WAL"
'
"$HARNESS_DIR/run-crash-target.sh" "$EVIDENCE_DIR" D09 lumen lumen-crash-target "$INLINE"

OUT="$EVIDENCE_DIR/D09.stdout.txt"
val() { grep -oE "$1=[A-Za-z0-9-]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val ready)" == "yes" ]] || { echo "FAIL: crash-target never signalled CRASH_TARGET_READY (seed precondition unmet)" >&2; cat "$EVIDENCE_DIR/crash-target.logs" >&2; exit 1; }

# 1. Canonical snapshot is whole-or-absent, NEVER torn.
SW=$(val snapshot_whole)
[[ "$SW" != "no" ]] || { echo "FAIL: canonical store.snapshot is TORN (does not parse) after a mid-snapshot kill; atomic-write violated" >&2; head -c 400 "$EVIDENCE_DIR/store.snapshot" >&2; exit 1; }

# 2. The acked datum survives in durable on-disk state (WAL or snapshot).
[[ "$(val acked_in_snapshot)" == "yes" || "$(val acked_in_wal)" == "yes" ]] \
    || { echo "FAIL: acked record '$BODY' not found in either store.snapshot or store.wal after the kill (lost durable datum)" >&2; echo "--- snapshot ---" >&2; head -c 400 "$EVIDENCE_DIR/store.snapshot" >&2; echo "--- wal ---" >&2; head -c 400 "$EVIDENCE_DIR/store.wal" >&2; exit 1; }

echo "OK — lumen snapshot atomicity holds under a mid-snapshot SIGKILL: canonical store.snapshot is whole-or-absent (whole=$(val snapshot_whole), present=$(val snapshot_present), tmp_at_kill=$(val tmp_at_kill)), never torn; the acked record '$BODY' survived in durable on-disk state (in_snapshot=$(val acked_in_snapshot), in_wal=$(val acked_in_wal))."
