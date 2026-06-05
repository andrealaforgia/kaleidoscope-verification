#!/usr/bin/env bash
# B08 — beacon SIGHUP reload REFUSES a malformed edit and keeps the
# previous catalogue: a reload that finds zero valid rules does NOT swap,
# does NOT crash, and does NOT re-page. The safety half of the reload
# contract (B03 pins the apply half). ADR-0063 + the DISCUSS domain
# examples (refuse on zero valid rules; keep the previous catalogue).
#
# Given beacon-server is firing rule A
# When the only rule file is then CORRUPTED (so a re-read yields zero
#      valid rules) and SIGHUP is delivered
# Then beacon emits `beacon.reload.refused` (previous_catalogue_retained),
#      the previous catalogue stays live (A still firing, EXACTLY ONE
#      incident — no re-page, state kept), and the process stays running.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b08-net-$$"; MOCK="b08-mock"; BEACON="b08-beacon-$$"
OUT_HOST="$(mktemp -d -t b08-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b08-rules-XXXXXX)"; cp "$EXP_DIR/rules/a.toml" "$RULES_HOST/a.toml"

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
docker run -d --name "$MOCK" --network "$NET" -e FIRING_WINDOW=1000 \
    -v "$EXP_DIR/mock/server.py:/mock/server.py:ro" -v "$OUT_HOST:/out" \
    python:3-slim python3 /mock/server.py >/dev/null
sleep 2
docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=info -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 4   # let A fire

# CORRUPT the only rule file so a re-read yields ZERO valid rules.
cat > "$RULES_HOST/a.toml" <<'BROKEN'
[[rules]]
name = "b08-rule-a"
query = "up == 0"
severity = "warning"
this_is_not_a_valid_field = "boom"
BROKEN
echo "corrupted a.toml; sending SIGHUP" >&2
docker kill -s HUP "$BEACON" >/dev/null 2>&1 || true
sleep 6

RUNNING=$(docker inspect -f '{{.State.Running}}' "$BEACON" 2>/dev/null || echo false)
docker logs "$BEACON" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true
cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true
echo "running_after_hup=$RUNNING" | tee "$EVIDENCE_DIR/observation.txt" >&2
echo "--- incidents ---" >&2; cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"
ERR="$EVIDENCE_DIR/beacon-server.stderr.txt"

# 1. The reload was REFUSED (not applied), keeping the previous catalogue.
grep -qE 'beacon\.reload\.refused' "$ERR" \
    || { echo "FAIL: no beacon.reload.refused on a zero-valid-rule edit; the reload was not refused" >&2; tail -20 "$ERR" >&2; exit 1; }
grep -qE 'previous_catalogue_retained' "$ERR" \
    || { echo "FAIL: refusal did not state previous_catalogue_retained" >&2; grep -i refused "$ERR" >&2; exit 1; }
# It must NOT have succeeded.
grep -qE 'beacon\.reload\.succeeded' "$ERR" \
    && { echo "FAIL: reload SUCCEEDED on a zero-valid-rule edit (should refuse)" >&2; grep -i reload "$ERR" >&2; exit 1; }

# 2. A kept firing with EXACTLY ONE incident (no re-page, state kept).
A_COUNT=$(jq -c 'select(.name=="b08-rule-a" and (.resolved_at==null))' "$INC" 2>/dev/null | grep -c . || echo 0)
[[ "$A_COUNT" -ge 1 ]] || { echo "FAIL: rule A never fired; fixture broken" >&2; cat "$INC" >&2; exit 1; }
[[ "$A_COUNT" -eq 1 ]] || { echo "FAIL: rule A fired ${A_COUNT} times — a refused reload must NOT re-page (state should be kept, A not restarted)" >&2; cat "$INC" >&2; exit 1; }
# A must not have been resolved (the previous catalogue stayed live).
A_RESOLVED=$(jq -c 'select(.name=="b08-rule-a" and (.resolved_at!=null))' "$INC" 2>/dev/null | head -1)
[[ -z "$A_RESOLVED" ]] || { echo "FAIL: A was resolved after the refused reload — previous catalogue was torn down" >&2; cat "$INC" >&2; exit 1; }

# 3. The process stayed up (no crash, no partial apply).
[[ "$RUNNING" == "true" ]] \
    || { echo "FAIL: beacon-server did not stay running after a refused reload (running=$RUNNING)" >&2; exit 1; }

echo "OK — beacon SIGHUP reload refuses a malformed (zero-valid-rule) edit and keeps the previous catalogue: beacon.reload.refused (previous_catalogue_retained) on stderr, rule A kept firing with EXACTLY ONE incident (no re-page, state kept by name), and the process stayed running. A bad edit does not take the alerting engine dark."
