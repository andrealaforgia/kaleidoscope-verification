#!/usr/bin/env bash
# B05 — beacon multi-sink routing: a rule with N configured sinks emits
# each incident to ALL of them (ADR-0035 fan-out).
#
# Reuses the Beacon harness with a path-recording mock: one rule declares
# two webhook sinks at distinct endpoints (/hook-a, /hook-b) on the same
# mock, which records {path, body} per POST. On the rule's Firing the same
# incident must land at BOTH endpoints.
#
# (Slice 04 also ships SMTP/Mattermost/Zulip/OnCall sinks and a
# Transient/Permanent delivery classification; those need their own
# protocol servers and are not pinned here. The webhook fan-out is the
# black-box-reachable core of the multi-sink contract.)
#
# Given a rule with two webhook sinks and an Active condition
# When beacon-server fires the rule
# Then the Firing incident is POSTed to BOTH sink endpoints.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b05-net-$$"
MOCK="b05-mock"
BEACON="b05-beacon-$$"
OUT_HOST="$(mktemp -d -t b05-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b05-rules-XXXXXX)"; cp "$EXP_DIR/rules/"*.toml "$RULES_HOST/"

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
docker run -d --name "$MOCK" --network "$NET" \
    -v "$EXP_DIR/mock/server.py:/mock/server.py:ro" \
    -v "$OUT_HOST:/out" \
    python:3-slim python3 /mock/server.py >/dev/null
sleep 2

docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=info -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 6
docker logs "$BEACON" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true
cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true

echo "--- deliveries captured ---" >&2; cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"
# The same firing incident at BOTH endpoints.
A=$(jq -c 'select(.path=="/hook-a" and .body.name=="b05-multi-sink" and (.body.resolved_at==null))' "$INC" 2>/dev/null | head -1)
B=$(jq -c 'select(.path=="/hook-b" and .body.name=="b05-multi-sink" and (.body.resolved_at==null))' "$INC" 2>/dev/null | head -1)
[[ -n "$A" ]] || { echo "FAIL: no Firing incident delivered to sink A (/hook-a)" >&2; cat "$INC" >&2; exit 1; }
[[ -n "$B" ]] || { echo "FAIL: no Firing incident delivered to sink B (/hook-b)" >&2; cat "$INC" >&2; exit 1; }

echo "OK — beacon multi-sink routing: the Firing incident for rule b05-multi-sink was POSTed to BOTH configured webhook sinks (/hook-a and /hook-b). Each incident fans out to every configured sink."
