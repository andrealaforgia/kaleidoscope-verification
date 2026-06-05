#!/usr/bin/env bash
# B01 — beacon-server boots, loads the well-formed rules, surfaces a
# malformed rule as a diagnostic WITHOUT preventing the good rule from
# scheduling, and stays running.
#
# Reuses the Beacon harness (harness/Dockerfile.beacon-server). No mock
# backend is needed: B01 is about boot + rule loading, so a dead --backend
# URL is fine (poll failures are per-tick and do not exit the process).
# The rules dir is mounted WRITABLE (beacon persists rule-state at
# <rules>/.beacon-state); a temp copy keeps the repo clean.
#
# Given a rules dir with one valid rule (good.toml) and one malformed rule
#       (bad.toml: an unknown field `frequency`)
# When beacon-server is started against it
# Then stderr shows a "rule load diagnostic" for the malformed file and
#      "beacon-server starting rules_loaded=1 diagnostics=1", and the
#      process stays running (the good rule scheduled despite the bad one).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NAME="b01-beacon-$$"
RULES_HOST="$(mktemp -d -t b01-rules-XXXXXX)"
cp "$EXP_DIR/rules/"*.toml "$RULES_HOST/"

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    rm -rf "$RULES_HOST"
}
trap cleanup EXIT

echo "step 1: build beacon-server from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.beacon-server" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

echo "step 2: run beacon-server with one good + one malformed rule" >&2
docker run -d --name "$NAME" \
    -e RUST_LOG=info -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://127.0.0.1:1/api/v1" >/dev/null
sleep 4
RUNNING=$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)
EXITCODE=$(docker inspect -f '{{.State.ExitCode}}' "$NAME" 2>/dev/null || echo NA)
# Strip any ANSI colour escapes so the assertions match cleanly.
docker logs "$NAME" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$NAME" >/dev/null 2>&1 || true

echo "running=$RUNNING exitcode=$EXITCODE" | tee "$EVIDENCE_DIR/observation.txt" >&2
echo "--- beacon stderr ---" >&2
cat "$EVIDENCE_DIR/beacon-server.stderr.txt" >&2

ERR="$EVIDENCE_DIR/beacon-server.stderr.txt"

# 1. The malformed rule was surfaced as a diagnostic.
grep -qE 'rule load diagnostic' "$ERR" \
    || { echo "FAIL: no 'rule load diagnostic' for the malformed rule" >&2; exit 1; }
# The diagnostic names the offending field (unknown field 'frequency').
grep -qiE 'frequency|unknown field' "$ERR" \
    || { echo "FAIL: diagnostic did not name the unknown field" >&2; exit 1; }

# 2. The good rule loaded despite the bad one: rules_loaded=1, diagnostics=1.
grep -qE 'beacon-server starting' "$ERR" \
    || { echo "FAIL: beacon-server did not reach the 'starting' line (it may have refused)" >&2; exit 1; }
grep -qE 'rules_loaded[=: ]+1' "$ERR" \
    || { echo "FAIL: expected rules_loaded=1 (the good rule), not found" >&2; exit 1; }
grep -qE 'diagnostics[=: ]+1' "$ERR" \
    || { echo "FAIL: expected diagnostics=1 (the bad rule), not found" >&2; exit 1; }

# 3. The process stayed up (did not crash on the malformed rule).
[[ "$RUNNING" == "true" ]] \
    || { echo "FAIL: beacon-server did not stay running (running=$RUNNING, exit=$EXITCODE)" >&2; exit 1; }

echo "OK — beacon-server boots with rules: loaded the well-formed rule (rules_loaded=1) and surfaced the malformed rule as a diagnostic (diagnostics=1, naming the unknown field 'frequency') WITHOUT refusing to start, and stayed running. Malformed rules are reported and skipped, not fatal."
