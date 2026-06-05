#!/usr/bin/env bash
# B09 — beacon SIGHUP reload applies the VALID new rule and SKIPS the
# malformed one with a per-file diagnostic (report-and-skip on reload,
# matching startup). The third reload branch: B03 = clean apply, B08 =
# full refuse (zero valid), B09 = partial apply + diagnostic.
#
# Given beacon-server is firing rule A
# When two files are added to the live rules dir — b.toml (VALID rule B)
#      and c.toml (MALFORMED, unknown field) — and SIGHUP is delivered
# Then the reload SUCCEEDS with at least one valid rule added: B starts
#      firing, the malformed c.toml is reported as a diagnostic and
#      SKIPPED (rule C never fires), A keeps firing, and the process is up.
#      A typo in one added rule does not block the good added rules.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b09-net-$$"; MOCK="b09-mock"; BEACON="b09-beacon-$$"
OUT_HOST="$(mktemp -d -t b09-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b09-rules-XXXXXX)"; cp "$EXP_DIR/rules/a.toml" "$RULES_HOST/a.toml"

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

# Add a VALID rule (b.toml) and a MALFORMED rule (c.toml), then SIGHUP.
cp "$EXP_DIR/add/b.toml" "$RULES_HOST/b.toml"
cp "$EXP_DIR/add/c.toml" "$RULES_HOST/c.toml"
echo "added b.toml (valid) + c.toml (malformed); sending SIGHUP" >&2
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

# 1. The reload SUCCEEDED with the valid rule added and a diagnostic.
grep -qE 'beacon\.reload\.succeeded' "$ERR" \
    || { echo "FAIL: reload did not succeed; a partly-broken edit that adds a valid rule should apply" >&2; tail -25 "$ERR" >&2; exit 1; }
grep -E 'beacon\.reload\.succeeded' "$ERR" | grep -qE 'added=1' \
    || { echo "FAIL: reload.succeeded did not report added=1 (the valid rule B)" >&2; grep 'reload.succeeded' "$ERR" >&2; exit 1; }
grep -E 'beacon\.reload\.succeeded' "$ERR" | grep -qE 'diagnostics=[1-9]' \
    || { echo "FAIL: reload.succeeded did not report a diagnostic for the malformed c.toml" >&2; grep 'reload.succeeded' "$ERR" >&2; exit 1; }

# 2. The added VALID rule B fired.
jq -e 'select(.name=="b09-rule-b" and (.resolved_at==null))' "$INC" >/dev/null 2>&1 \
    || { echo "FAIL: added valid rule B never fired after the reload" >&2; cat "$INC" >&2; exit 1; }
# 3. The malformed rule C was SKIPPED (never fired).
jq -e 'select(.name=="b09-rule-c")' "$INC" >/dev/null 2>&1 \
    && { echo "FAIL: malformed rule C fired — it should have been skipped" >&2; cat "$INC" >&2; exit 1; }
# 4. A kept firing; process up.
jq -e 'select(.name=="b09-rule-a")' "$INC" >/dev/null 2>&1 \
    || { echo "FAIL: rule A missing; fixture broken" >&2; cat "$INC" >&2; exit 1; }
[[ "$RUNNING" == "true" ]] || { echo "FAIL: beacon-server did not stay running (running=$RUNNING)" >&2; exit 1; }

echo "OK — beacon SIGHUP reload applies the valid new rule and skips the malformed one: beacon.reload.succeeded (added=1, diagnostics>=1), added rule B fired, malformed rule C was reported-and-skipped (never fired), A kept firing, process up. A typo in one added rule does not block the good ones (report-and-skip on reload, matching startup)."
