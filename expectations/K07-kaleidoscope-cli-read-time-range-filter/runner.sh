#!/usr/bin/env bash
# K07 — `read --since <ISO> --until <ISO>` returns only the records
# whose observed_time_unix_nano falls in the half-open interval.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
INPUT=/tmp/input.ndjson
cat > "$INPUT" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"event-a","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000060000000000,"severity_number":9,"severity_text":"INFO","body":"event-b","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000120000000000,"severity_number":9,"severity_text":"INFO","body":"event-c","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$INPUT" >/dev/null 2>&1
# Window covering only event-b: [1700000030, 1700000090) nanos → ISO mid-points.
# 1700000060 = 2023-11-14T22:14:20Z
# Pick a window [2023-11-14T22:14:00Z, 2023-11-14T22:14:30Z) — covers event-b only? event-b at 22:14:20Z so yes; event-a at 22:13:20Z, event-c at 22:15:20Z, both excluded.
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data --since 2023-11-14T22:14:00Z --until 2023-11-14T22:14:30Z > /tmp/win.out 2>&1
cat /tmp/win.out
# Count actual NDJSON record lines (skip the "read ok: records=N" diagnostic).
LINES=$(grep -c "^{" /tmp/win.out || true)
echo "lines=$LINES"
cp /tmp/win.out "'"$EVIDENCE_DIR"'/windowed.ndjson"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K07 "$INLINE"

LINES=$(grep -oE 'lines=[0-9]+' "$EVIDENCE_DIR/K07.stdout.txt" | cut -d= -f2)
echo "  windowed lines: $LINES"
[[ "$LINES" == "1" ]] || { echo "expected 1, got $LINES" >&2; exit 1; }
grep -q "event-b" "$EVIDENCE_DIR/windowed.ndjson" || { echo "missing event-b" >&2; exit 1; }
grep -q "event-a" "$EVIDENCE_DIR/windowed.ndjson" && { echo "should not contain event-a" >&2; exit 1; } || true
grep -q "event-c" "$EVIDENCE_DIR/windowed.ndjson" && { echo "should not contain event-c" >&2; exit 1; } || true
echo "OK — read --since/--until filters to the window (event-b only)"
