#!/usr/bin/env bash
# K13 — `kaleidoscope-cli ingest` is NON-ATOMIC: a malformed NDJSON line
# mid-stream aborts with a non-zero exit, but earlier batches that
# already flushed are LEFT COMMITTED, and re-running the same input
# DOUBLE-INGESTS the committed prefix (Lumen append has no dedup).
#
# DEFAULT_BATCH_SIZE = 100 (crates/kaleidoscope-cli/src/lib.rs:70), no
# --batch-size flag. So 100 valid records (batch 1 flushes at line 100)
# followed by a malformed line 101 leaves the first 100 durably ingested
# while ingest exits non-zero on the parse error.
#
# Documents the footgun in the four-quadrants kaleidoscope-cli report
# (Q2 MEDIUM, partial-batch commit / re-run double-ingest); filed as
# issue 009. The SAFE half (typed error + non-zero exit, no corruption)
# is real restraint; the partial-commit + double-ingest is the defect.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/k13.ndjson
{
  for i in $(seq 1 100); do
    printf "{\"observed_time_unix_nano\":%d,\"severity_number\":9,\"severity_text\":\"INFO\",\"body\":\"k13-rec-%03d\",\"attributes\":{},\"resource_attributes\":{\"service.name\":\"k13\"},\"trace_id\":null,\"span_id\":null}\n" "$((1000+i))" "$i"
  done
  printf "{this-is-not-valid-json line 101\n"
} > "$INPUT"
echo "input_lines=$(wc -l < "$INPUT" | tr -d " ")"

ingest_once() {
  local ec=0
  docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" > /tmp/ig.out 2>&1 || ec=$?
  echo "$ec"
}
read_count() {
  docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data > /tmp/rd.out 2>/tmp/rd.err || true
  grep -c "k13-rec-" /tmp/rd.out
}

EC1=$(ingest_once); echo "ingest1_exit=$EC1"; cp /tmp/ig.out "'"$EVIDENCE_DIR"'/ingest1.out"
N1=$(read_count);   echo "count_after_1=$N1"
EC2=$(ingest_once); echo "ingest2_exit=$EC2"
N2=$(read_count);   echo "count_after_2=$N2"; cp /tmp/rd.out "'"$EVIDENCE_DIR"'/read-after-2.ndjson"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K13 "$INLINE"

OUT="$EVIDENCE_DIR/K13.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

# (a) SAFE: both ingests abort non-zero on the malformed line.
[[ "$(val ingest1_exit)" != "0" ]] || { echo "ingest1 should exit non-zero on the malformed line" >&2; exit 1; }
[[ "$(val ingest2_exit)" != "0" ]] || { echo "ingest2 should exit non-zero on the malformed line" >&2; exit 1; }
# (b) NON-ATOMIC: the first 100 (one flushed batch) are committed despite the abort.
[[ "$(val count_after_1)" == "100" ]] || { echo "expected 100 committed after the aborted ingest (partial commit), got $(val count_after_1)" >&2; exit 1; }
# (c) DOUBLE-INGEST: re-running the same input commits another 100.
[[ "$(val count_after_2)" == "200" ]] || { echo "expected 200 after re-run (double-ingest), got $(val count_after_2)" >&2; exit 1; }

echo "OK — non-atomic ingest confirmed (issue 009): a malformed line 101 aborts non-zero, but the flushed batch of 100 is committed (count_after_1=100), and re-running the same input double-ingests it (count_after_2=200). SAFE half holds (typed abort, no corruption); partial-commit + double-ingest is the footgun."
