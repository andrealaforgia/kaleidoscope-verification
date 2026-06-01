#!/usr/bin/env bash
# Q01 — `query-api` started without `KALEIDOSCOPE_QUERY_TENANT`
# refuses to bind the listener: it exits non-zero AND emits an
# `event=health.startup.refused` line on stderr with the tenant
# reason. Anchors the fail-closed tenancy invariant from ADR-0042
# DD9 (Earned-Trust: wire -> probe -> use), verified by the
# `composition::probe` unit test
# `tenant_resolution_is_fail_closed_on_unset_or_empty`.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
# Mount a fresh /data so the Pulse store can be opened; we are
# testing the tenant gate, not the store gate.
docker run --rm \
    -v "$DATA_HOST:/data" \
    -e RUST_LOG=info \
    "$QAPI_IMAGE" > /tmp/qapi.out 2> /tmp/qapi.err || EC=$?
echo "exit=$EC"
echo "---stdout (first 10 lines)---"
head -10 /tmp/qapi.out
echo "---stderr (first 20 lines)---"
head -20 /tmp/qapi.err
cp /tmp/qapi.err "'"$EVIDENCE_DIR"'/query-api.stderr.txt"
cp /tmp/qapi.out "'"$EVIDENCE_DIR"'/query-api.stdout.txt"
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" Q01 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/Q01.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$EC" != "0" ]] || { echo "expected non-zero exit (fail-closed); got $EC" >&2; exit 1; }

# Structured-event assertion (tightened 2026-06-01 at 2663eb5, after
# read-api-tracing-subscriber-v0 landed; issue 005 resolved). The
# binary now installs query_http_common::init_tracing, so the
# fail-closed arm emits a structured JSON `health.startup.refused`
# (level ERROR) on stderr BEFORE the non-zero exit, not just the bare
# Err() text. We assert on the structured event: locate the JSON line
# carrying event=health.startup.refused and verify via jq that it is
# ERROR level and its reason names the tenant fail-closed.
SERR="$EVIDENCE_DIR/query-api.stderr.txt"
REFUSAL=$(grep '"event":"health.startup.refused"' "$SERR" | head -1)
[[ -n "$REFUSAL" ]] || { echo "stderr lacks structured health.startup.refused event" >&2; cat "$SERR" >&2; exit 1; }
echo "$REFUSAL" | jq -e '.level=="ERROR" and (.reason|contains("KALEIDOSCOPE_QUERY_TENANT")) and (.reason|contains("fail-closed"))' >/dev/null \
    || { echo "health.startup.refused event is not ERROR-level or lacks the tenant fail-closed reason" >&2; echo "$REFUSAL" >&2; exit 1; }
# The bare Err() line still prints too; keep asserting it as a
# belt-and-braces operator-visible signal.
grep -qE 'KALEIDOSCOPE_QUERY_TENANT.*unset.*fail-closed' "$SERR" || \
    { echo "stderr lacks tenant fail-closed reason in the bare Err line" >&2; exit 1; }
echo "OK — query-api fails closed without KALEIDOSCOPE_QUERY_TENANT (exit=${EC}; structured JSON event=health.startup.refused level=ERROR on stderr + bare Err line)"
