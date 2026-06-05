#!/usr/bin/env bash
# B07 — beacon inhibition RELEASE: when the inhibitor X resolves, the
# Firing of the inhibited rule Y that was suppressed while X fired is
# RELEASED to Y's sinks. The other half of the inhibition contract
# (B04 pins the suppression; B07 pins the release). ADR-0035.
#
# Query-aware mock: X's query (`up == 0`) is Active for FIRING_WINDOW=5s
# then Inactive (X fires, then resolves); Y's query (`latency_seconds > 1`)
# is Active throughout. So: X fires (~1s); Y reaches Firing (~1s) but is
# suppressed while X fires; X resolves (~6s); on X's Resolved the resolver
# releases Y's held Firing, which reaches the sink (~6s) -- AFTER X
# resolved.
#
# Given X inhibits Y, both Active, X firing first and then resolving
# When beacon-server evaluates them
# Then the sink sees X-firing, then X-resolved, then Y-firing (released),
#      with Y-firing arriving only after X resolved.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b07-net-$$"; MOCK="b07-mock"; BEACON="b07-beacon-$$"
OUT_HOST="$(mktemp -d -t b07-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b07-rules-XXXXXX)"; cp "$EXP_DIR/rules/"*.toml "$RULES_HOST/"

cleanup() {
    docker rm -f "$BEACON" "$MOCK" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    rm -rf "$OUT_HOST" "$RULES_HOST"
}
trap cleanup EXIT

echo "step 1: build beacon-server" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.beacon-server" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

docker network create "$NET" >/dev/null
docker run -d --name "$MOCK" --network "$NET" -e FIRING_WINDOW=9 \
    -v "$EXP_DIR/mock/server.py:/mock/server.py:ro" -v "$OUT_HOST:/out" \
    python:3-slim python3 /mock/server.py >/dev/null
sleep 2
docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=info -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 15   # X fires ~1s, X resolves ~6s, Y released ~6s
docker logs "$BEACON" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true
cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true
echo "--- deliveries (t = seconds since start) ---" >&2; cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"
# X firing and X resolved.
XF=$(jq -c 'select(.body.name=="b07-x-inhibitor" and (.body.resolved_at==null))' "$INC" 2>/dev/null | head -1)
XR=$(jq -c 'select(.body.name=="b07-x-inhibitor" and (.body.resolved_at!=null))' "$INC" 2>/dev/null | head -1)
[[ -n "$XF" ]] || { echo "FAIL: X never fired" >&2; cat "$INC" >&2; exit 1; }
[[ -n "$XR" ]] || { echo "FAIL: X never resolved (mock did not flip X inactive, or resolve not emitted)" >&2; cat "$INC" >&2; exit 1; }

# Y firing must be present (released) and arrive AFTER X resolved.
T_XR=$(printf '%s' "$XR" | jq -r '.t')
YF_T=$(jq -r 'select(.body.name=="b07-y-inhibited" and (.body.resolved_at==null)) | .t' "$INC" 2>/dev/null | head -1)
[[ -n "$YF_T" ]] || { echo "FAIL: Y's Firing was never released to the sink (suppressed and lost, not deferred)" >&2; cat "$INC" >&2; exit 1; }
awk -v y="$YF_T" -v x="$T_XR" 'BEGIN{exit !(y+0 >= x+0)}' \
    || { echo "FAIL: Y fired at t=$YF_T BEFORE X resolved at t=$T_XR; that is not a release-on-resolve" >&2; cat "$INC" >&2; exit 1; }

echo "OK — beacon inhibition RELEASE on resolve: X fired then resolved (t=$T_XR), and Y's suppressed Firing was RELEASED to the sink at t=$YF_T (>= X-resolve). The suppressed alert was deferred, not lost: it is delivered once the inhibitor clears. Completes the inhibition contract with B04."
