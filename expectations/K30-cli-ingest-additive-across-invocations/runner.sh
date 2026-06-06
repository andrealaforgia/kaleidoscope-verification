#!/usr/bin/env bash
# K30 — two separate `ingest` runs into the same data dir are ADDITIVE:
# the second appends, it does not overwrite. A subsequent read returns
# both batches. Covers UC-CLI-006 (additive across invocations); the
# separate read container also exercises UC-CLI-008 (survives restart).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
echo "{\"observed_time_unix_nano\":1700000000000000000,\"severity_number\":9,\"severity_text\":\"INFO\",\"body\":\"first\",\"attributes\":{},\"resource_attributes\":{},\"trace_id\":null,\"span_id\":null}" \
  | docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data > /tmp/i1.out 2>&1
echo "{\"observed_time_unix_nano\":1700000060000000000,\"severity_number\":9,\"severity_text\":\"INFO\",\"body\":\"second\",\"attributes\":{},\"resource_attributes\":{},\"trace_id\":null,\"span_id\":null}" \
  | docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data > /tmp/i2.out 2>&1
echo "---ingest 1---"; cat /tmp/i1.out; echo "---ingest 2---"; cat /tmp/i2.out
cp /tmp/i1.out "'"$EVIDENCE_DIR"'/ingest-1.out"; cp /tmp/i2.out "'"$EVIDENCE_DIR"'/ingest-2.out"
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data > /tmp/read.out 2>/dev/null
echo "---read bodies---"; jq -r .body /tmp/read.out | tr "\n" " "; echo
cp /tmp/read.out "'"$EVIDENCE_DIR"'/read.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K30 "$INLINE"

BODIES=$(jq -r .body "$EVIDENCE_DIR/read.out" | sort | tr '\n' ' ')
[[ "$BODIES" == "first second " ]] || { echo "second ingest overwrote the first (read bodies: $BODIES)" >&2; exit 1; }
echo "OK — two ingests are additive: both 'first' and 'second' present after the second run"
