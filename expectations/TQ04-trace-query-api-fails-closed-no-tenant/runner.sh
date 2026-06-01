#!/usr/bin/env bash
# TQ04 — trace-query-api started without KALEIDOSCOPE_TRACE_QUERY_TENANT
# fails closed: refuses to bind, exits non-zero, AND (since
# read-api-tracing-subscriber-v0, 2663eb5) emits a STRUCTURED JSON
# `health.startup.refused` event at ERROR level on stderr before the
# exit. Mirrors Q01/LQ06 for the trace read binary; completes the
# issue-005 resolution across all three read binaries.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
docker run --rm \
    -v "$DATA_HOST:/data" \
    -e RUST_LOG=info \
    "$TQAPI_IMAGE" > /tmp/tq.out 2> /tmp/tq.err || EC=$?
echo "exit=$EC"
echo "---stderr---"; cat /tmp/tq.err
cp /tmp/tq.err "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt"
cp /tmp/tq.out "'"$EVIDENCE_DIR"'/trace-query-api.stdout.txt"
'
"$HARNESS_DIR/run-trace-query-api.sh" "$EVIDENCE_DIR" TQ04 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/TQ04.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" != "0" ]] || { echo "expected non-zero exit (fail-closed); got $EC" >&2; exit 1; }

SERR="$EVIDENCE_DIR/trace-query-api.stderr.txt"
REFUSAL=$(grep '"event":"health.startup.refused"' "$SERR" | head -1)
[[ -n "$REFUSAL" ]] || { echo "stderr lacks structured health.startup.refused event" >&2; cat "$SERR" >&2; exit 1; }
echo "$REFUSAL" | jq -e '.level=="ERROR" and (.reason|contains("TRACE_QUERY_TENANT")) and (.reason|contains("fail-closed"))' >/dev/null \
    || { echo "health.startup.refused not ERROR-level or reason lacks TRACE_QUERY_TENANT fail-closed" >&2; echo "$REFUSAL" >&2; exit 1; }

echo "OK — trace-query-api fails closed without KALEIDOSCOPE_TRACE_QUERY_TENANT (exit=${EC}; structured JSON event=health.startup.refused level=ERROR on stderr)"
