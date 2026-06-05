#!/usr/bin/env bash
# B04 — beacon inhibition collapses an alert storm: while inhibitor X is
# Firing, the Firing of an inhibited rule Y is SUPPRESSED (held pending,
# not delivered to Y's sinks). KPI3 storm-collapse (ADR-0035).
#
# Determinism: X has for_duration=0s so it fires on the first Active tick
# (~1s); Y has for_duration=4s so it only reaches Firing (~5s) AFTER X is
# already Firing. The shared InhibitionResolver therefore sees X.firing
# when Y's Firing arrives and holds Y pending. The mock keeps both queries
# Active throughout (FIRING_WINDOW large), so X never resolves and Y stays
# suppressed. RUST_LOG=debug captures Y's state transition to Firing, so
# Y's absence at the sink is proven to be SUPPRESSION, not "Y never fired".
#
# Given rules X (inhibits Y) and Y, both Active, X firing before Y
# When beacon-server evaluates them with a shared webhook sink
# Then X's Firing incident reaches the sink and Y's does NOT, while Y is
#      observed reaching Firing internally.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b04-net-$$"
MOCK="b04-mock"
BEACON="b04-beacon-$$"
OUT_HOST="$(mktemp -d -t b04-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b04-rules-XXXXXX)"; cp "$EXP_DIR/rules/"*.toml "$RULES_HOST/"

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
echo "step 2: start mock (both queries Active throughout)" >&2
docker run -d --name "$MOCK" --network "$NET" \
    -e FIRING_WINDOW=100 \
    -v "$EXP_DIR/mock/server.py:/mock/server.py:ro" \
    -v "$OUT_HOST:/out" \
    python:3-slim python3 /mock/server.py >/dev/null
sleep 2

echo "step 3: run beacon-server ~8s (X fires ~1s, Y reaches Firing ~5s, suppressed)" >&2
docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=debug -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 8
docker logs "$BEACON" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true
cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true

echo "--- incidents captured ---" >&2; cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"
ERR="$EVIDENCE_DIR/beacon-server.stderr.txt"

# 1. X's Firing reached the sink.
X_AT_SINK=$(jq -c 'select(.name=="b04-x-inhibitor")' "$INC" 2>/dev/null | head -1)
[[ -n "$X_AT_SINK" ]] || { echo "FAIL: inhibitor X did not reach the sink (no incident name=b04-x-inhibitor)" >&2; cat "$INC" >&2; echo "--- stderr ---" >&2; tail -30 "$ERR" >&2; exit 1; }

# 2. Y reached Firing INTERNALLY (so its sink-absence is suppression, not
#    "never fired"). The debug state-transition line names to:Firing.
grep -qE 'b04-y-inhibited' "$ERR" || { echo "FAIL: rule Y never appears in beacon logs; fixture broken" >&2; tail -40 "$ERR" >&2; exit 1; }
grep -E 'b04-y-inhibited' "$ERR" | grep -qiE 'to.?:?.?Firing|Firing' \
    || { echo "FAIL: rule Y was not observed reaching Firing internally; cannot distinguish suppression from never-fired" >&2; grep 'b04-y-inhibited' "$ERR" >&2; exit 1; }

# 3. Y's Firing was SUPPRESSED: it did NOT reach the sink.
Y_AT_SINK=$(jq -c 'select(.name=="b04-y-inhibited" and (.resolved_at == null))' "$INC" 2>/dev/null | head -1)
[[ -z "$Y_AT_SINK" ]] || { echo "FAIL: inhibited Y's Firing reached the sink despite X firing (storm NOT collapsed)" >&2; cat "$INC" >&2; exit 1; }

echo "OK — beacon inhibition collapses the storm: inhibitor b04-x-inhibitor fired and reached the webhook sink, while inhibited b04-y-inhibited reached Firing internally (debug state-transition observed) but its Firing was SUPPRESSED and did NOT reach the sink while X was firing. KPI3 storm-collapse verified black-box."
