#!/usr/bin/env bash
# D08 — lumen WAL-fsync REFUSAL on a lying substrate (black-box).
#
# store-fsync-durability-v0 wired each store's composition root to probe
# the fsync substrate BEFORE opening for writes: a substrate that lies
# about durability (acks an fsync that did not reach stable storage) is
# refused, so no datum is ever acked against a substrate proven to lie.
# This is the observable half of the WAL-fsync AC that a post-ack process
# kill CANNOT prove (the page cache hides flush-vs-fsync from an external
# kill). The implementer shipped `lumen-crash-target --probe-lying` to
# surface that refusal out-of-process; D08 asserts on it.
#
# Given the lumen composition root is driven against a LyingFsyncBackend
# When `lumen-crash-target --probe-lying` runs
# Then it refuses to open the store: emits `event=health.startup.refused`
#      with a `substrate=` descriptor on stderr, and exits non-zero,
#      WITHOUT ever opening the store for writes.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
docker run --rm -e KALEIDOSCOPE_CRASH_PILLAR_ROOT=/data -v "$DATA_HOST:/data" \
    "$CT_IMAGE" --probe-lying > /tmp/d08.out 2> /tmp/d08.err || EC=$?
echo "probe_exit=$EC"
cp /tmp/d08.err "'"$EVIDENCE_DIR"'/probe-lying.stderr"
cp /tmp/d08.out "'"$EVIDENCE_DIR"'/probe-lying.stdout"
# Did the refused store leave any write behind? It must not: the contract
# is refuse-before-open, so /data carries no store/ payload.
ls -laR "$DATA_HOST" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
echo "wal_present=$([[ -f "$DATA_HOST/store.wal" || -f "$DATA_HOST/store/lumen.wal" ]] && echo yes || echo no)"
echo "---stderr---"; head -5 /tmp/d08.err
'
"$HARNESS_DIR/run-crash-target.sh" "$EVIDENCE_DIR" D08 lumen lumen-crash-target "$INLINE"

OUT="$EVIDENCE_DIR/D08.stdout.txt"
ERRLINE="$EVIDENCE_DIR/probe-lying.stderr"
val() { grep -oE "$1=[A-Za-z0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

EC=$(val probe_exit)
# 1. Non-zero exit: the store refused to open.
[[ "$EC" != "0" ]] || { echo "FAIL: --probe-lying exited 0; a lying substrate was NOT refused" >&2; cat "$ERRLINE" >&2; exit 1; }
# 2. Observable refusal event on stderr with a substrate descriptor.
grep -qE 'event=health\.startup\.refused' "$ERRLINE" \
    || { echo "FAIL: no health.startup.refused event on stderr" >&2; cat "$ERRLINE" >&2; exit 1; }
grep -qE 'substrate=[A-Za-z0-9-]+' "$ERRLINE" \
    || { echo "FAIL: refusal carried no substrate= descriptor" >&2; cat "$ERRLINE" >&2; exit 1; }
# 3. It must NOT be the unexpected-pass branch (the substrate must have
#    been caught lying, not silently passed).
grep -qE 'substrate=fsync-unexpected-pass' "$ERRLINE" \
    && { echo "FAIL: lying substrate was not detected (unexpected-pass)" >&2; cat "$ERRLINE" >&2; exit 1; }
# 4. Refuse-BEFORE-open: no store payload was written for the refused run.
[[ "$(val wal_present)" == "no" ]] \
    || { echo "FAIL: a WAL was written despite the refusal (write happened before/after refuse)" >&2; cat "$EVIDENCE_DIR/data-listing.txt" >&2; exit 1; }

SUBSTRATE=$(grep -oE 'substrate=[A-Za-z0-9-]+' "$ERRLINE" | tail -1 | cut -d= -f2)
echo "OK — lumen refuses a lying fsync substrate: --probe-lying exited ${EC}, emitted event=health.startup.refused substrate=${SUBSTRATE}, and wrote no store payload (refuse-before-open). This is the WAL-fsync wiring's observable refusal, which a post-ack process kill cannot prove."
