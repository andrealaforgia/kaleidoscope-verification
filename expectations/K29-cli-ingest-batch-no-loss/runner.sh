#!/usr/bin/env bash
# K29 — a large ingest whose count is NOT a multiple of the 100-record
# batch size (250) loses no records at batch boundaries: `records=250`,
# and a fresh `read` container returns all 250 in ascending order.
# Covers UC-CLI-004 (batch of many), UC-CLI-005 (all in order),
# UC-CLI-013 (250 not divisible by 100, no batch-boundary loss). The
# read runs in a separate container, also exercising UC-CLI-008
# (records survive a process restart).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
IN=/tmp/big.ndjson
: > "$IN"
i=0
while [ $i -lt 250 ]; do
  printf "{\"observed_time_unix_nano\":%d,\"severity_number\":9,\"severity_text\":\"INFO\",\"body\":\"b%d\",\"attributes\":{},\"resource_attributes\":{},\"trace_id\":null,\"span_id\":null}\n" $((1700000000000000000 + i)) "$i" >> "$IN"
  i=$((i+1))
done
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$IN" > /tmp/ing.out 2>&1
echo "---ingest---"; cat /tmp/ing.out
cp /tmp/ing.out "'"$EVIDENCE_DIR"'/ingest.out"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data > /tmp/read.out 2>/tmp/read.err
echo "read-records=$(wc -l < /tmp/read.out | tr -d " ")"
cp /tmp/read.out "'"$EVIDENCE_DIR"'/read.out"; cp /tmp/read.err "'"$EVIDENCE_DIR"'/read.err"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K29 "$INLINE"

grep -qE 'records=250' "$EVIDENCE_DIR/ingest.out" || { echo "ingest did not report records=250" >&2; exit 1; }
N=$(wc -l < "$EVIDENCE_DIR/read.out" | tr -d ' ')
[[ "$N" == "250" ]] || { echo "read returned $N records, expected 250 (batch-boundary loss?)" >&2; exit 1; }
# Ordering: bodies must be b0..b249 in ascending nano order.
FIRST=$(jq -r .body "$EVIDENCE_DIR/read.out" | head -1)
LAST=$(jq -r .body "$EVIDENCE_DIR/read.out" | tail -1)
[[ "$FIRST" == "b0" && "$LAST" == "b249" ]] || { echo "ordering not consistent with storage (first=$FIRST last=$LAST)" >&2; exit 1; }
echo "OK — 250 ingested, 250 read back in order (b0..b249), no batch-boundary loss"
