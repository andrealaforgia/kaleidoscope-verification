#!/usr/bin/env bash
# assert-snapshot-atomicity.sh — shared body for the per-store SNAPSHOT
# ATOMICITY expectations (the D09 pattern, generalised to the stores
# whose --seed-then-loop-snapshot takes no --body).
#
# store-fsync-durability-v0 writes each snapshot atomically (ADR-0060 §2):
# serialise to `store.snapshot.tmp`, fsync, rename onto `store.snapshot`,
# fsync the parent dir. A crash at ANY instant must leave the canonical
# path whole-or-absent (never torn); a stray `.tmp` is ignored on reopen.
# Because the rename precedes the WAL truncate, the single seeded acked
# datum is always held wholly by at least one of WAL or snapshot. This is
# the black-box ground for issue 007 (non-atomic snapshot can brick the
# store / lose data).
#
# Each crash-target seeds exactly ONE acked datum, prints
# CRASH_TARGET_READY only after it is durable, then loops snapshots. So a
# non-empty durable state == that datum survived.
#
# Args: $1=EVIDENCE_DIR  $2=LABEL  $3=CRATE  $4=BIN
set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
CRATE="$3"
BIN="$4"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="'"$LABEL"'-crash-$$"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" \
    -e KALEIDOSCOPE_CRASH_PILLAR_ROOT=/data \
    -v "$DATA_HOST:/data" \
    "$CT_IMAGE" --seed-then-loop-snapshot >/dev/null
READY=no
for _ in $(seq 1 100); do
    docker logs "$NAME" 2>/dev/null | grep -q CRASH_TARGET_READY && { READY=yes; break; }
    sleep 0.1
done
echo "ready=$READY"
sleep 0.3
TMP_AT_KILL=no; [[ -f "$DATA_HOST/store.snapshot.tmp" ]] && TMP_AT_KILL=yes
echo "tmp_at_kill=$TMP_AT_KILL"
docker kill -s KILL "$NAME" >/dev/null 2>&1 || true
docker logs "$NAME" > /tmp/'"$LABEL"'.logs 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

ls -laR "$DATA_HOST" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
cp "$DATA_HOST/store.snapshot" "'"$EVIDENCE_DIR"'/store.snapshot" 2>/dev/null || echo "(no canonical snapshot)" > "'"$EVIDENCE_DIR"'/store.snapshot"
cp "$DATA_HOST/store.wal" "'"$EVIDENCE_DIR"'/store.wal" 2>/dev/null || echo "(no wal)" > "'"$EVIDENCE_DIR"'/store.wal"
cp /tmp/'"$LABEL"'.logs "'"$EVIDENCE_DIR"'/crash-target.logs" 2>/dev/null || true

SNAP_PRESENT=no; [[ -f "$DATA_HOST/store.snapshot" ]] && SNAP_PRESENT=yes
echo "snapshot_present=$SNAP_PRESENT"
SNAP_WHOLE=na
if [[ "$SNAP_PRESENT" == yes ]]; then
    if jq -e . "$DATA_HOST/store.snapshot" >/dev/null 2>&1; then SNAP_WHOLE=yes; else SNAP_WHOLE=no; fi
fi
echo "snapshot_whole=$SNAP_WHOLE"
# Record survived: the (whole) snapshot carries at least one scalar leaf
# nested at depth >= 2, OR the WAL is non-empty. Schema-agnostic: a record
# in an array-of-records (lumen/ray/...) or a map-of-records (beacon rules)
# both yield deep scalar leaves; an EMPTY store ({"rules":{}}, {"traces":[]})
# has none, and a top-level metadata scalar (depth 1) is excluded.
IN_SNAP=no
[[ "$SNAP_WHOLE" == yes ]] && jq -e "[paths(scalars) | select(length >= 2)] | length >= 1" "$DATA_HOST/store.snapshot" >/dev/null 2>&1 && IN_SNAP=yes
IN_WAL=no
if [[ -f "$DATA_HOST/store.wal" ]]; then
    while IFS= read -r line; do [[ -n "$line" ]] && { IN_WAL=yes; break; }; done < "$DATA_HOST/store.wal"
fi
echo "record_in_snapshot=$IN_SNAP"
echo "record_in_wal=$IN_WAL"
'
"$HARNESS_DIR/run-crash-target.sh" "$EVIDENCE_DIR" "$LABEL" "$CRATE" "$BIN" "$INLINE"

OUT="$EVIDENCE_DIR/${LABEL}.stdout.txt"
val() { grep -oE "$1=[A-Za-z0-9-]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val ready)" == "yes" ]] || { echo "FAIL: crash-target never signalled CRASH_TARGET_READY (seed precondition unmet)" >&2; cat "$EVIDENCE_DIR/crash-target.logs" >&2; exit 1; }
SW=$(val snapshot_whole)
[[ "$SW" != "no" ]] || { echo "FAIL: canonical store.snapshot is TORN (does not parse) after a mid-snapshot kill; atomic-write violated" >&2; head -c 400 "$EVIDENCE_DIR/store.snapshot" >&2; exit 1; }
[[ "$(val record_in_snapshot)" == "yes" || "$(val record_in_wal)" == "yes" ]] \
    || { echo "FAIL: the seeded acked datum survived in neither store.snapshot nor store.wal after the kill (lost durable datum)" >&2; echo "--- snapshot ---" >&2; head -c 400 "$EVIDENCE_DIR/store.snapshot" >&2; echo "--- wal ---" >&2; head -c 200 "$EVIDENCE_DIR/store.wal" >&2; exit 1; }

echo "OK — ${CRATE} snapshot atomicity holds under a mid-snapshot SIGKILL: canonical store.snapshot is whole-or-absent (whole=$(val snapshot_whole), present=$(val snapshot_present), tmp_at_kill=$(val tmp_at_kill)), never torn; the seeded acked datum survived in durable on-disk state (in_snapshot=$(val record_in_snapshot), in_wal=$(val record_in_wal)). Black-box ground for issue 007."
