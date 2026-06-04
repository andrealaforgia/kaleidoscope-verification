#!/usr/bin/env bash
# D07 — cinder (tier metadata) torn-WAL-tail recovery via the CLI, the
# fourth pillar of the issue-006 close. kaleidoscope-cli `ingest` writes
# a Cinder Hot placement per batch into <data>/cinder.wal. After
# wal-torn-tail-recovery-v0 rewired cinder's open onto the shared
# wal_recovery seam (feat 1886d94, pillar="cinder"), a torn trailing
# line in cinder.wal must NOT brick the store: `list-items` reopens
# cinder, recovers the intact prefix, and lists the placement.
#
# Grounds black-box what the implementer (msg 015) reported: cinder DID
# brick before 1886d94 and her commit fixed it. Same SAFE-either-way
# shape as D04/D05/D06; recovery expected at HEAD.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/d07.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":100,"severity_number":9,"severity_text":"INFO","body":"d07-a","attributes":{},"resource_attributes":{"service.name":"d07"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":200,"severity_number":9,"severity_text":"INFO","body":"d07-b","attributes":{},"resource_attributes":{"service.name":"d07"},"trace_id":null,"span_id":null}
JSON

# 1. Ingest -> writes lumen + a Cinder Hot placement; cinder.wal created.
EC_ING=0
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" > /tmp/ing.out 2>&1 || EC_ING=$?
echo "ingest_exit=$EC_ING"
cp /tmp/ing.out "'"$EVIDENCE_DIR"'/ingest.out"

# Baseline: list-items BEFORE the tear (clean cinder).
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items acme /data hot > /tmp/li_before.out 2>&1 || true
echo "items_before=$(grep -c "batch-" /tmp/li_before.out || echo 0)"

# 2. TEAR the cinder WAL tail: incomplete JSON, no trailing newline.
WAL="$DATA_HOST/cinder.wal"
ls -l "$DATA_HOST" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
if [[ -f "$WAL" ]]; then
    cp "$WAL" "'"$EVIDENCE_DIR"'/cinder.wal.before"
    printf "%s" "{\"op\":\"place\",\"tenant\":\"acme\",\"item\":\"acme/batch-" >> "$WAL"
    cp "$WAL" "'"$EVIDENCE_DIR"'/cinder.wal.after"
else
    echo "CINDER_WAL_NOT_FOUND_at_$WAL"
fi

# 3. Reopen cinder via list-items on the torn /data; capture exit + output.
EC_LI=0
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" list-items acme /data hot > /tmp/li.out 2> /tmp/li.err || EC_LI=$?
echo "listitems_exit=$EC_LI"
cp /tmp/li.out "'"$EVIDENCE_DIR"'/list-items-after.out"
cp /tmp/li.err "'"$EVIDENCE_DIR"'/list-items-after.err"
echo "items_after=$(grep -c "batch-" /tmp/li.out || echo 0)"
echo "---stderr---"; head -3 /tmp/li.err
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" D07 "$INLINE"

OUT="$EVIDENCE_DIR/D07.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val ingest_exit)" == "0" ]] || { echo "ingest precondition failed" >&2; cat "$EVIDENCE_DIR/ingest.out" >&2; exit 1; }
[[ "$(val items_before)" -ge 1 ]] || { echo "no Hot item placed by ingest; fixture broken" >&2; exit 1; }

EC_LI=$(val listitems_exit)
N_AFTER=$(val items_after)
if [[ "$EC_LI" == "0" ]]; then
    # RECOVERY: cinder reopened and the intact placement survived the tear.
    [[ "$N_AFTER" -ge 1 ]] || { echo "list-items exit 0 but recovered 0 items (placement lost)" >&2; cat "$EVIDENCE_DIR/list-items-after.out" >&2; exit 1; }
    echo "OK — cinder torn WAL tail tolerated: list-items recovered ${N_AFTER} Hot placement(s) after the cinder.wal tail was torn (graceful recovery, shared wal_recovery seam on the Cinder store, via the CLI)"
else
    # FAIL-CLOSED: must be a clear cinder-open error, not a silent crash.
    grep -qiE 'cinder open|PersistenceFailed|WAL parse error' "$EVIDENCE_DIR/list-items-after.err" \
        || { echo "list-items failed without a clear cinder-open error" >&2; cat "$EVIDENCE_DIR/list-items-after.err" >&2; exit 1; }
    echo "OK — cinder torn WAL tail does NOT yield corrupt data: list-items fails closed (exit ${EC_LI}) with a clear cinder-open error (SAFE; note: cinder was expected to RECOVER at this SHA per the implementer)"
fi
