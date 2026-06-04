#!/usr/bin/env bash
# assert-probe-lying-refusal.sh — shared body for the per-store WAL-fsync
# REFUSAL expectations (the D08 pattern, generalised).
#
# Every store shipped by store-fsync-durability-v0 carries a
# `<store>-crash-target --probe-lying` mode that drives the composition
# root against a LyingFsyncBackend and must REFUSE to open: emit
# `event=health.startup.refused substrate=<descriptor>` on stderr, exit
# non-zero, and write NO store payload (refuse before open). This is the
# observable half of the WAL-fsync AC that a post-ack process kill cannot
# prove (the page cache hides flush-vs-fsync). The fsync-IS-wired count
# stays in-suite (CountingFsyncBackend) and is credited to the implementer.
#
# Args: $1=EVIDENCE_DIR  $2=LABEL  $3=CRATE  $4=BIN
set -euo pipefail
EVIDENCE_DIR="$1"
LABEL="$2"
CRATE="$3"
BIN="$4"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
docker run --rm -e KALEIDOSCOPE_CRASH_PILLAR_ROOT=/data -v "$DATA_HOST:/data" \
    "$CT_IMAGE" --probe-lying > /tmp/'"$LABEL"'.out 2> /tmp/'"$LABEL"'.err || EC=$?
echo "probe_exit=$EC"
cp /tmp/'"$LABEL"'.err "'"$EVIDENCE_DIR"'/probe-lying.stderr"
cp /tmp/'"$LABEL"'.out "'"$EVIDENCE_DIR"'/probe-lying.stdout"
ls -laR "$DATA_HOST" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
# Layout-independent: refuse-before-open means no WAL or snapshot payload
# of any name was written.
PAYLOAD=$(find "$DATA_HOST" \( -name "*.wal" -o -name "*.snapshot" \) 2>/dev/null | head -1)
echo "payload_written=$([[ -n "$PAYLOAD" ]] && echo yes || echo no)"
echo "---stderr---"; head -5 /tmp/'"$LABEL"'.err
'
"$HARNESS_DIR/run-crash-target.sh" "$EVIDENCE_DIR" "$LABEL" "$CRATE" "$BIN" "$INLINE"

OUT="$EVIDENCE_DIR/${LABEL}.stdout.txt"
ERRLINE="$EVIDENCE_DIR/probe-lying.stderr"
val() { grep -oE "$1=[A-Za-z0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

EC=$(val probe_exit)
[[ "$EC" != "0" ]] || { echo "FAIL: --probe-lying exited 0; a lying substrate was NOT refused" >&2; cat "$ERRLINE" >&2; exit 1; }
grep -qE 'event=health\.startup\.refused' "$ERRLINE" \
    || { echo "FAIL: no health.startup.refused event on stderr" >&2; cat "$ERRLINE" >&2; exit 1; }
grep -qE 'substrate=[A-Za-z0-9-]+' "$ERRLINE" \
    || { echo "FAIL: refusal carried no substrate= descriptor" >&2; cat "$ERRLINE" >&2; exit 1; }
grep -qE 'substrate=fsync-unexpected-pass' "$ERRLINE" \
    && { echo "FAIL: lying substrate was not detected (unexpected-pass)" >&2; cat "$ERRLINE" >&2; exit 1; }
[[ "$(val payload_written)" == "no" ]] \
    || { echo "FAIL: a store payload was written despite the refusal (not refuse-before-open)" >&2; cat "$EVIDENCE_DIR/data-listing.txt" >&2; exit 1; }

SUBSTRATE=$(grep -oE 'substrate=[A-Za-z0-9-]+' "$ERRLINE" | tail -1 | cut -d= -f2)
echo "OK — ${CRATE} refuses a lying fsync substrate: --probe-lying exited ${EC}, emitted event=health.startup.refused substrate=${SUBSTRATE}, and wrote no store payload (refuse-before-open). WAL-fsync wiring's observable refusal, which a post-ack process kill cannot prove."
