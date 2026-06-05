#!/usr/bin/env bash
# B03 — beacon-server reloads its rule catalogue on SIGHUP (the documented
# contract). Grounds issue 010 black-box.
#
# Docs (c4-context/container, slice-02, wave-decisions) promise hot reload
# on SIGHUP: edit the rules dir, send SIGHUP, the new catalogue takes
# effect without a restart. This runner tests that promise: start with
# rule A only, add rule B to the live rules dir, send SIGHUP, and watch
# whether B begins firing.
#
# Transition-proof (the A17 pattern): GREEN if the added rule fires after
# SIGHUP (reload works); RED if it does not while the process survives
# (the documented reload is a silent no-op = issue 010); FAIL-loud if
# SIGHUP kills the process (a different gap).
#
# Both A and B query the always-Active mock, so B fires iff it is loaded.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b03-net-$$"
MOCK="b03-mock"
BEACON="b03-beacon-$$"
OUT_HOST="$(mktemp -d -t b03-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b03-rules-XXXXXX)"
cp "$EXP_DIR/mock/server.py" "$RULES_HOST/.keep-mock" 2>/dev/null || true
rm -f "$RULES_HOST/.keep-mock"
# Start with rule A only.
cp "$EXP_DIR/rules/a.toml" "$RULES_HOST/a.toml"

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

START_T=$(date -u +%s)
docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=info -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 4   # let rule A fire

# Add rule B to the LIVE rules dir, then SIGHUP (the documented reload).
cp "$EXP_DIR/rules/b.toml" "$RULES_HOST/b.toml"
echo "added b.toml; sending SIGHUP" >&2
docker kill -s HUP "$BEACON" >/dev/null 2>&1 || true
sleep 6   # if reload works, B fires within its for_duration

RUNNING=$(docker inspect -f '{{.State.Running}}' "$BEACON" 2>/dev/null || echo false)
EXITCODE=$(docker inspect -f '{{.State.ExitCode}}' "$BEACON" 2>/dev/null || echo NA)
docker logs "$BEACON" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true
cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true
echo "running_after_hup=$RUNNING exitcode=$EXITCODE" | tee "$EVIDENCE_DIR/observation.txt" >&2
echo "--- incidents ---" >&2; cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"
A_FIRED=$(jq -c 'select(.name=="b03-rule-a")' "$INC" 2>/dev/null | head -1)
B_FIRED=$(jq -c 'select(.name=="b03-rule-b")' "$INC" 2>/dev/null | head -1)

# Precondition: rule A must have fired (the fixture + mock work).
[[ -n "$A_FIRED" ]] || { echo "FAIL: rule A never fired; fixture/mock broken, cannot test reload" >&2; cat "$INC" >&2; tail -20 "$EVIDENCE_DIR/beacon-server.stderr.txt" >&2; exit 1; }

if [[ -n "$B_FIRED" ]]; then
    echo "GREEN (reload works) — after SIGHUP the added rule b03-rule-b began firing: beacon-server hot-reloaded the rule catalogue. issue 010 resolved." >&2
    exit 0
fi

# B did not fire. Distinguish silent no-op from a process death.
if [[ "$RUNNING" == "true" ]]; then
    echo "RED (issue 010) — SIGHUP is a SILENT NO-OP: the added rule b03-rule-b never fired, beacon-server kept running the original catalogue (running=$RUNNING), and there is no reload. The documented SIGHUP hot-reload (c4/slice-02/wave-decisions) is absent. Flips GREEN if a SIGHUP reload handler lands." >&2
    exit 1
fi
echo "RED (issue 010, worse) — SIGHUP did not reload AND the process is no longer running (running=$RUNNING, exit=$EXITCODE): SIGHUP neither reloaded nor was handled cleanly." >&2
exit 1
