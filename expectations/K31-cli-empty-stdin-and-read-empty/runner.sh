#!/usr/bin/env bash
# K31 — empty stdin `ingest` is a no-op success (records=0, exit 0, store
# left valid), and a subsequent `read` of the now-initialised store
# returns nothing with `read ok: records=0`. Covers UC-CLI-014 (empty
# stdin no-op) and UC-CLI-007 (read an empty store).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
: | docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data > /tmp/ing.out 2>&1
echo "ingest-exit=$?" > /tmp/ing.rc
echo "---empty-stdin ingest---"; cat /tmp/ing.rc; cat /tmp/ing.out
cp /tmp/ing.out "'"$EVIDENCE_DIR"'/ingest.out"; cp /tmp/ing.rc "'"$EVIDENCE_DIR"'/ingest.rc"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data > /tmp/read.out 2>/tmp/read.err
echo "read-exit=$?" > /tmp/read.rc
echo "---read empty store---"; cat /tmp/read.rc; echo "[stdout]"; cat /tmp/read.out; echo "[stderr]"; cat /tmp/read.err
cp /tmp/read.out "'"$EVIDENCE_DIR"'/read.out"; cp /tmp/read.err "'"$EVIDENCE_DIR"'/read.err"; cp /tmp/read.rc "'"$EVIDENCE_DIR"'/read.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K31 "$INLINE"

grep -qx 'ingest-exit=0' "$EVIDENCE_DIR/ingest.rc" || { echo "empty-stdin ingest did not exit 0" >&2; exit 1; }
grep -qE 'records=0' "$EVIDENCE_DIR/ingest.out" || { echo "empty-stdin ingest did not report records=0" >&2; exit 1; }
grep -qx 'read-exit=0' "$EVIDENCE_DIR/read.rc" || { echo "read of empty store did not exit 0" >&2; exit 1; }
[[ -s "$EVIDENCE_DIR/read.out" ]] && { echo "read of empty store emitted records on stdout" >&2; exit 1; }
grep -qF 'read ok: records=0' "$EVIDENCE_DIR/read.err" || { echo "read of empty store did not report records=0" >&2; exit 1; }
echo "OK — empty-stdin ingest is a no-op success; read of the empty store is records=0"
