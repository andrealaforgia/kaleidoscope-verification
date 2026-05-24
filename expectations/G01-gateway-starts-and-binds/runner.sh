#!/usr/bin/env bash
# G01 — `kaleidoscope-gateway` started with a writable pillar
# root and `KALEIDOSCOPE_DEFAULT_TENANT` set comes up healthy:
# aperture (which the gateway delegates to via `aperture::spawn`)
# emits `event=ready` on stderr within a short window. This is
# the operator-observable startup-success signal.
#
# Note: the gateway's own `tracing::info!(event="gateway_starting")`
# from `crates/kaleidoscope-gateway/src/main.rs` is DROPPED at HEAD
# because main.rs installs no tracing subscriber and aperture
# installs one only post-spawn. Same pattern as query-api;
# tracked under issue 005. We assert on `event=ready` because it
# fires AFTER the subscriber is up.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="g01-$$"
docker run --rm -d \
    --name "$NAME" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 4318:4318 \
    "$GW_IMAGE" > /dev/null
# Stream logs to file in the background.
docker logs -f "$NAME" > /tmp/gw.out 2> /tmp/gw.err &
LOGS_PID=$!
# Poll for the aperture-via-gateway readiness signal for up
# to 30 s. (See header comment for why this is the right event
# at HEAD rather than gateway_starting.)
SAW=""
for i in $(seq 1 30); do
    if grep -q "\"event\":\"ready\"" /tmp/gw.err 2>/dev/null; then
        SAW="yes"
        break
    fi
    sleep 1
done
docker stop --time 5 "$NAME" >/dev/null 2>&1 || true
kill $LOGS_PID 2>/dev/null || true
echo "saw_ready=$SAW"
echo "---stderr head---"
head -30 /tmp/gw.err
cp /tmp/gw.err "'"$EVIDENCE_DIR"'/gateway.stderr.txt"
cp /tmp/gw.out "'"$EVIDENCE_DIR"'/gateway.stdout.txt"
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G01 "$INLINE"

SAW=$(grep -oE 'saw_ready=[a-z]*' "$EVIDENCE_DIR/G01.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$SAW" == "yes" ]] || { echo "event=ready not observed within 30 s" >&2; exit 1; }
grep -q '"event":"ready"' "$EVIDENCE_DIR/gateway.stderr.txt" || \
    { echo "stderr lacks event=ready (defensive recheck)" >&2; exit 1; }
echo "OK — gateway came up healthy: aperture emitted event=ready on stderr"
