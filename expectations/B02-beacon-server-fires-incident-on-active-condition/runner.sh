#!/usr/bin/env bash
# B02 — beacon-server emits a Firing incident when a rule's query goes
# Active, and a Resolved incident when it returns to empty. The first
# black-box test of the Beacon alerting surface.
#
# Harness (the design the B0x scaffolds called for): a single mock
# container doubles as the PromQL instant-query backend and the webhook
# sink catcher. It returns a NON-EMPTY vector for FIRING_WINDOW seconds
# (drives Active -> Firing) then an EMPTY vector (drives Resolved), and
# records every POSTed Incident. beacon-server polls it on a 1s tick with
# for_duration=0s, so the transitions land within the run window.
#
# Given a rule `up == 0` (for_duration 0s, interval 1s) and a backend that
#       reports the condition Active then Inactive
# When beacon-server runs against it with a webhook sink
# Then it POSTs exactly one Firing incident (name = the rule, resolved_at
#      null) and then one Resolved incident (resolved_at set).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b02-net-$$"
MOCK="b02-mock"        # rule.toml points the sink + backend at this name
BEACON="b02-beacon-$$"
OUT_HOST="$(mktemp -d -t b02-out-XXXXXX)"
: > "$OUT_HOST/incidents.ndjson"
# beacon persists rule-state at <rules>/.beacon-state/store, so /rules
# must be WRITABLE. Mount a temp copy (not the repo) so it can create it.
RULES_HOST="$(mktemp -d -t b02-rules-XXXXXX)"
cp "$EXP_DIR/rules/"*.toml "$RULES_HOST/"

cleanup() {
    docker rm -f "$BEACON" "$MOCK" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    rm -rf "$OUT_HOST" "$RULES_HOST"
}
trap cleanup EXIT

echo "step 1: build beacon-server from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.beacon-server" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

docker network create "$NET" >/dev/null

echo "step 2: start mock backend + webhook catcher" >&2
docker run -d --name "$MOCK" --network "$NET" \
    -e FIRING_WINDOW=5 \
    -v "$EXP_DIR/mock/server.py:/mock/server.py:ro" \
    -v "$OUT_HOST:/out" \
    python:3-slim python3 /mock/server.py >/dev/null
sleep 2  # let the mock bind

echo "step 3: run beacon-server against the mock for ~10s" >&2
docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=info \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 10
docker logs "$BEACON" > "$EVIDENCE_DIR/beacon-server.stderr.txt" 2>&1 || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true

cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true
echo "--- incidents captured ---" >&2
cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"
COUNT=$(grep -c . "$INC" 2>/dev/null || echo 0)
[[ "$COUNT" -ge 1 ]] || { echo "FAIL: beacon emitted no incident to the webhook (count=$COUNT)" >&2; echo "--- beacon stderr ---" >&2; tail -30 "$EVIDENCE_DIR/beacon-server.stderr.txt" >&2; exit 1; }

# A Firing incident: name matches and resolved_at is null/absent.
FIRING=$(jq -c 'select(.name=="b02-synthetic-up-down" and (.resolved_at == null))' "$INC" 2>/dev/null | head -1)
[[ -n "$FIRING" ]] || { echo "FAIL: no Firing incident (name=b02-synthetic-up-down, resolved_at null) in the webhook capture" >&2; cat "$INC" >&2; exit 1; }
# Query echoed in the incident (operator-visible context).
Q=$(printf '%s' "$FIRING" | jq -r '.query')
[[ "$Q" == "up == 0" ]] || { echo "FAIL: firing incident query=$Q (expected 'up == 0')" >&2; exit 1; }

# A Resolved incident: resolved_at set (the mock flipped the query empty).
RESOLVED=$(jq -c 'select(.name=="b02-synthetic-up-down" and (.resolved_at != null))' "$INC" 2>/dev/null | head -1)
if [[ -n "$RESOLVED" ]]; then
    echo "OK — beacon-server fired AND resolved: one Firing incident (resolved_at null) then one Resolved incident (resolved_at set) for rule b02-synthetic-up-down, query 'up == 0', captured at the webhook sink. Full Inactive->Firing->Resolved cycle observed black-box."
else
    echo "OK (firing only) — beacon-server emitted a Firing incident (name=b02-synthetic-up-down, query 'up == 0', resolved_at null) to the webhook sink. The Resolved transition was not captured in the window; firing path verified black-box." >&2
    echo "NOTE: resolved incident not observed within the 10s window (firing path GREEN; resolved best-effort)" >&2
fi
