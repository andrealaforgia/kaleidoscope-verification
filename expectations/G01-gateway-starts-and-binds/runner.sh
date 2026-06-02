#!/usr/bin/env bash
# G01 — `kaleidoscope-gateway` started with a writable pillar root and
# `KALEIDOSCOPE_DEFAULT_TENANT` set comes up healthy and announces its
# OWN structured lifecycle on stderr, in order:
#   gateway_starting   (info, fields incl. pillar_root)
#   listener_bound     (info, fields transport, addr)
# with gateway_starting emitted BEFORE listener_bound.
#
# Tightened 2026-06-02 at caa8cdf, after gateway-tracing-subscriber-v0
# landed (the gateway now installs a JSON tracing subscriber EARLY in
# main, before any event). Before that, gateway_starting was emitted
# before aperture::spawn installed its subscriber and was dropped (the
# "ordering gap"); G01 used to assert on aperture's post-spawn
# `event=ready` instead. This resolves the gateway half of issue 005.
#
# Host-port note (N27): the gateway binds the FIXED internal ports
# 4317/4318; we publish 4318 to a UNIQUE high host port so a parallel
# dev-side `kaleidoscope-e2e` compose stack squatting 4317-4318 does
# not collide. The container's internal bind is private to its netns.
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
    -p 14329:4318 \
    "$GW_IMAGE" > /dev/null
# Poll until the gateway announces its bound listener (or 30 s).
SAW=""
for i in $(seq 1 30); do
    docker logs "$NAME" 2>/tmp/gw.err >/tmp/gw.out || true
    if grep -q "\"event\":\"listener_bound\"" /tmp/gw.err 2>/dev/null; then
        SAW="yes"; break
    fi
    sleep 1
done
docker logs "$NAME" > /tmp/gw.out 2> /tmp/gw.err || true
docker stop --time 5 "$NAME" >/dev/null 2>&1 || true
echo "saw_listener_bound=$SAW"
cp /tmp/gw.err "'"$EVIDENCE_DIR"'/gateway.stderr.txt"
cp /tmp/gw.out "'"$EVIDENCE_DIR"'/gateway.stdout.txt"
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G01 "$INLINE"

SERR="$EVIDENCE_DIR/gateway.stderr.txt"
SAW=$(grep -oE 'saw_listener_bound=[a-z]*' "$EVIDENCE_DIR/G01.stdout.txt" | tail -1 | cut -d= -f2)
[[ "$SAW" == "yes" ]] || { echo "listener_bound not observed within 30 s" >&2; head -30 "$SERR" >&2; exit 1; }

# Both structured events present, as JSON, at info level.
GS_LINE=$(grep -nF '"event":"gateway_starting"' "$SERR" | head -1 | cut -d: -f1)
LB_LINE=$(grep -nF '"event":"listener_bound"'   "$SERR" | head -1 | cut -d: -f1)
[[ -n "$GS_LINE" ]] || { echo "stderr lacks structured gateway_starting event" >&2; head -30 "$SERR" >&2; exit 1; }
[[ -n "$LB_LINE" ]] || { echo "stderr lacks structured listener_bound event" >&2; exit 1; }
# Each line is valid JSON carrying the expected level.
grep -F '"event":"gateway_starting"' "$SERR" | head -1 | jq -e '.level=="INFO"' >/dev/null \
    || { echo "gateway_starting is not a JSON INFO event" >&2; exit 1; }
# The gateway binds two listeners (grpc :4317 and http :4318); assert
# the http one is present as a JSON INFO event with transport=http.
grep -F '"event":"listener_bound"' "$SERR" | grep -F '"transport":"http"' | head -1 \
    | jq -e '.level=="INFO" and .transport=="http"' >/dev/null \
    || { echo "no listener_bound JSON INFO event with transport=http" >&2; grep listener_bound "$SERR" >&2; exit 1; }
# Ordering: gateway_starting BEFORE listener_bound (the ordering-gap fix).
[[ "$GS_LINE" -lt "$LB_LINE" ]] || { echo "ordering wrong: gateway_starting (line $GS_LINE) not before listener_bound (line $LB_LINE)" >&2; exit 1; }

echo "OK — gateway announces its own structured lifecycle: JSON gateway_starting (INFO) THEN listener_bound (INFO, transport=http) on stderr, in order (issue 005 gateway half resolved)"
