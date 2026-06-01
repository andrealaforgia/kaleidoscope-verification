#!/usr/bin/env bash
# LQ06 — log-query-api started without KALEIDOSCOPE_LOG_QUERY_TENANT
# fails closed: it refuses to bind the listener, exits non-zero, AND
# (since read-api-tracing-subscriber-v0, 2663eb5) emits a STRUCTURED
# JSON `health.startup.refused` event at ERROR level on stderr before
# the exit. Mirrors Q01 for the log read binary; the structured-event
# assertion is the issue-005 resolution carried onto log-query-api.
# Anchors ADR-0042 fail-closed (Earned-Trust wire->probe->use) +
# read-api-tracing-subscriber-v0.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
# Mount a fresh /data so the Lumen store can be opened; we are testing
# the tenant gate, not the store gate. NO KALEIDOSCOPE_LOG_QUERY_TENANT.
docker run --rm \
    -v "$DATA_HOST:/data" \
    -e RUST_LOG=info \
    "$LQAPI_IMAGE" > /tmp/lq.out 2> /tmp/lq.err || EC=$?
echo "exit=$EC"
echo "---stderr---"; cat /tmp/lq.err
cp /tmp/lq.err "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt"
cp /tmp/lq.out "'"$EVIDENCE_DIR"'/log-query-api.stdout.txt"
'
"$HARNESS_DIR/run-log-query-api.sh" "$EVIDENCE_DIR" LQ06 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/LQ06.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" != "0" ]] || { echo "expected non-zero exit (fail-closed); got $EC" >&2; exit 1; }

SERR="$EVIDENCE_DIR/log-query-api.stderr.txt"
REFUSAL=$(grep '"event":"health.startup.refused"' "$SERR" | head -1)
[[ -n "$REFUSAL" ]] || { echo "stderr lacks structured health.startup.refused event" >&2; cat "$SERR" >&2; exit 1; }
echo "$REFUSAL" | jq -e '.level=="ERROR" and (.reason|contains("LOG_QUERY_TENANT")) and (.reason|contains("fail-closed"))' >/dev/null \
    || { echo "health.startup.refused not ERROR-level or reason lacks LOG_QUERY_TENANT fail-closed" >&2; echo "$REFUSAL" >&2; exit 1; }

echo "OK — log-query-api fails closed without KALEIDOSCOPE_LOG_QUERY_TENANT (exit=${EC}; structured JSON event=health.startup.refused level=ERROR on stderr)"
