#!/usr/bin/env bash
# K33 — round-trip field fidelity beyond K03: severity_number/text across
# the TRACE..FATAL span are preserved, a unicode + escaped-control body is
# intact, and records carrying differing service.name keep their own
# resource attributes. Covers UC-CLI-010 (severity preserved), UC-CLI-011
# (unicode/escaped body), UC-CLI-012 (resource attrs / service identity).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
IN=/tmp/fid.ndjson
cat > "$IN" <<JSON
{"observed_time_unix_nano":100,"severity_number":1,"severity_text":"TRACE","body":"trace-line","attributes":{},"resource_attributes":{"service.name":"alpha"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":200,"severity_number":21,"severity_text":"FATAL","body":"fatal-line","attributes":{},"resource_attributes":{"service.name":"beta"},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":300,"severity_number":9,"severity_text":"INFO","body":"héllo 世界 ✓ tab\there","attributes":{},"resource_attributes":{"service.name":"gamma"},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$IN" >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data > /tmp/read.out 2>/dev/null
echo "---read---"; cat /tmp/read.out
cp /tmp/read.out "'"$EVIDENCE_DIR"'/read.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K33 "$INLINE"

R="$EVIDENCE_DIR/read.out"
sev() { jq -r "select(.resource_attributes.\"service.name\"==\"$1\") | \"\(.severity_number)/\(.severity_text)\"" "$R"; }
[[ "$(sev alpha)" == "1/TRACE" ]]  || { echo "TRACE severity not preserved for service alpha: $(sev alpha)" >&2; exit 1; }
[[ "$(sev beta)"  == "21/FATAL" ]] || { echo "FATAL severity not preserved for service beta: $(sev beta)" >&2; exit 1; }
# Unicode + escaped-control body intact on the gamma record.
GBODY=$(jq -r 'select(.resource_attributes."service.name"=="gamma") | .body' "$R")
printf '%s' "$GBODY" | grep -qF '世界' || { echo "unicode CJK lost from body" >&2; exit 1; }
printf '%s' "$GBODY" | grep -qF '✓'   || { echo "unicode symbol (U+2713) lost from body" >&2; exit 1; }
TAB=$(printf '\t')
printf '%s' "$GBODY" | grep -qF "$TAB" || { echo "escaped tab control char lost from body" >&2; exit 1; }
echo "OK — severity TRACE/FATAL preserved, unicode+escaped body intact, per-record service.name kept"
