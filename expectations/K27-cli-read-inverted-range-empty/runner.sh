#!/usr/bin/env bash
# K27 — an inverted window (`--since` after `--until`) is a calm empty
# result, NOT an error: exit 0, `read ok: records=0`, no record lines.
# Covers UC-RANGE-011.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
IN=/tmp/in.ndjson
cat > "$IN" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"t0","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000060000000000,"severity_number":9,"severity_text":"INFO","body":"t60","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$IN" >/dev/null 2>&1

docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    --since 2023-11-14T22:14:20Z --until 2023-11-14T22:13:20Z \
    > /tmp/inv.out 2>/tmp/inv.err
echo "inv-exit=$?" > /tmp/inv.rc
echo "---inverted---"; cat /tmp/inv.rc
echo "[stdout]"; cat /tmp/inv.out
echo "[stderr]"; cat /tmp/inv.err
cp /tmp/inv.out "'"$EVIDENCE_DIR"'/inverted.out"
cp /tmp/inv.err "'"$EVIDENCE_DIR"'/inverted.err"
cp /tmp/inv.rc  "'"$EVIDENCE_DIR"'/inverted.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K27 "$INLINE"

grep -qx 'inv-exit=0' "$EVIDENCE_DIR/inverted.rc" || { echo "inverted range did not exit 0 (should be calm empty, not error)" >&2; exit 1; }
[[ -s "$EVIDENCE_DIR/inverted.out" ]] && { echo "inverted range emitted record lines on stdout (should be empty)" >&2; exit 1; }
grep -qF 'read ok: records=0' "$EVIDENCE_DIR/inverted.err" || { echo "inverted range did not report records=0" >&2; exit 1; }
echo "OK — inverted window is a calm empty result (exit 0, records=0, no rows)"
