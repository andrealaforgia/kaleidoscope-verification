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
EC1=$(val ingest1_exit); EC2=$(val ingest2_exit)
N1=$(val count_after_1); N2=$(val count_after_2)

# SAFE invariant (holds atomic OR non-atomic): a malformed line always
# aborts with a non-zero exit and never serves corrupt data.
[[ "$EC1" != "0" ]] || { echo "FAIL: ingest1 should exit non-zero on the malformed line" >&2; exit 1; }
[[ "$EC2" != "0" ]] || { echo "FAIL: ingest2 should exit non-zero on the malformed line" >&2; exit 1; }

# Transition-proof classification (grounds issue 009; the A17/B03 pattern).
# ATOMIC (the contract): all-or-nothing — a file with any malformed line
# commits NOTHING, no matter how many times it is run.
if [[ "$N1" == "0" && "$N2" == "0" ]]; then
    echo "GREEN (atomic) — kaleidoscope-cli ingest is all-or-nothing: a malformed line aborts non-zero and commits NOTHING (count_after_1=0), and re-running the same bad input still commits nothing (count_after_2=0). No partial commit, no double-ingest. issue 009 resolved." >&2
    exit 0
fi
# NON-ATOMIC (the defect): a flushed batch is left committed and a re-run
# double-ingests it.
if [[ "$N1" == "100" && "$N2" == "200" ]]; then
    echo "RED (issue 009) — kaleidoscope-cli ingest is NON-ATOMIC: the malformed line 101 aborts non-zero but the flushed batch of 100 is left COMMITTED (count_after_1=100), and re-running the same input DOUBLE-INGESTS it (count_after_2=200). Partial-commit + double-ingest. Flips GREEN when cli-ingest-atomic-v0 (ADR-0064, buffer-all-then-flush) lands." >&2
    exit 1
fi
echo "FAIL — indeterminate ingest atomicity: count_after_1=$N1, count_after_2=$N2 (expected atomic 0/0 or the non-atomic 100/200). The fixture or the batch size may have changed; re-examine." >&2
cat "$EVIDENCE_DIR/read-after-2.ndjson" 2>/dev/null | head -5 >&2
exit 2
