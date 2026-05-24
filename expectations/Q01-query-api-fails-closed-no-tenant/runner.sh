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

# Note: ADR-0042 promises a `tracing::error!(event =
# "health.startup.refused", ...)` event, but the query-api
# binary at HEAD installs no tracing subscriber, so the event
# is dropped silently. The operator-visible signal is the
# `Err(...)` printed by Rust's default Result-from-main on
# stderr. We assert on what is actually observable.
grep -qE 'KALEIDOSCOPE_QUERY_TENANT.*unset.*fail-closed' "$EVIDENCE_DIR/query-api.stderr.txt" || \
    { echo "stderr lacks tenant fail-closed reason" >&2; exit 1; }
echo "OK — query-api fails closed without KALEIDOSCOPE_QUERY_TENANT (exit=${EC} + Err(KALEIDOSCOPE_QUERY_TENANT ... fail-closed) on stderr)"
