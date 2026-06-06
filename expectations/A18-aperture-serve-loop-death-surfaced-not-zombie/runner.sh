#!/usr/bin/env bash
# A18 — aperture SURFACES a post-bind serving-loop death instead of
# leaving a silent zombie listener (ADR-0066,
# aperture-serve-loop-error-surfacing-v0).
#
# Before the fix, a gRPC/HTTP serving loop that died AFTER binding was
# swallowed at transport.rs (`let _ = server.await`), so the process kept
# running with a bound-but-dead listener — a silent zombie an operator
# could not detect. The fix makes the death self-react: a structured
# `event=serve_loop_failed`, a readiness flip to the sticky `Failed`
# phase (`/readyz` → 503 "failed"), and process exit code 3.
#
# The implementer ships a runtime trigger,
# `APERTURE_TEST_INJECT_SERVE_FAILURE=grpc|http`, that routes through the
# EXACT production emit + verdict path (the aperture analogue of cinder's
# FailingFsyncBackend), so this is black-box reachable end to end.
#
# Given aperture started with the serve-failure injected for a transport
# When the post-bind serving loop dies with no shutdown requested
# Then aperture emits `event=serve_loop_failed transport=<t>` (ERROR),
#      flips readiness (`readiness_changed ready=false
#      reason=serve_loop_failed`), and exits 3 — NOT a lingering zombie.
#      Negative control: with no injection, aperture binds and stays up
#      (ready=true), proving exit-3 is the death surfacing, not a generic
#      startup failure.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a18"

echo "step 1: build aperture from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

# Run aperture with a given injection value; capture exit + stderr.
# $1=label $2=inject-value-or-empty $3=http-host-port
run_aperture() {
    local label="$1" inject="$2" hport="$3"
    local name="a18-${label}-$$"
    docker rm -f "$name" >/dev/null 2>&1 || true
    local envargs=(-e NO_COLOR=1 -e RUST_LOG=info)
    [[ -n "$inject" ]] && envargs+=(-e "APERTURE_TEST_INJECT_SERVE_FAILURE=$inject")
    docker run -d --name "$name" "${envargs[@]}" \
        -v "$EXP_DIR/aperture.toml:/etc/aperture/aperture.toml:ro" \
        -p "${hport}:4318" \
        "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null 2>&1
    sleep 4
    local running exitc
    running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)
    exitc=$(docker inspect -f '{{.State.ExitCode}}' "$name" 2>/dev/null || echo NA)
    docker logs "$name" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/${label}.stderr.txt" || true
    echo "${label}_running=$running" | tee -a "$EVIDENCE_DIR/observation.txt"
    echo "${label}_exit=$exitc"      | tee -a "$EVIDENCE_DIR/observation.txt"
    docker rm -f "$name" >/dev/null 2>&1 || true
}

: > "$EVIDENCE_DIR/observation.txt"
echo "step 2: inject grpc serve-loop death" >&2
run_aperture grpc grpc 34318
echo "step 3: inject http serve-loop death" >&2
run_aperture http http 34319
echo "step 4: negative control (no injection)" >&2
run_aperture none "" 34320

OBS="$EVIDENCE_DIR/observation.txt"
val() { grep -oE "$1=[A-Za-z0-9]+" "$OBS" | tail -1 | cut -d= -f2; }

assert_surfaced() {
    local t="$1"
    local err="$EVIDENCE_DIR/${t}.stderr.txt"
    [[ "$(val ${t}_exit)" == "3" ]] || { echo "FAIL: ${t} injection — expected exit 3, got $(val ${t}_exit)" >&2; tail -10 "$err" >&2; exit 1; }
    [[ "$(val ${t}_running)" == "false" ]] || { echo "FAIL: ${t} injection — aperture still running (zombie), did not exit" >&2; exit 1; }
    grep -qE "\"event\":\"serve_loop_failed\".*\"transport\":\"${t}\"" "$err" \
        || { echo "FAIL: ${t} — no serve_loop_failed event for transport=${t}" >&2; tail -10 "$err" >&2; exit 1; }
    grep -qE "\"event\":\"readiness_changed\".*\"ready\":\"false\".*serve_loop_failed" "$err" \
        || { echo "FAIL: ${t} — readiness did not flip to false (reason=serve_loop_failed)" >&2; tail -10 "$err" >&2; exit 1; }
}
assert_surfaced grpc
assert_surfaced http

# Negative control: no injection -> aperture binds and STAYS UP (ready).
[[ "$(val none_running)" == "true" ]] || { echo "FAIL: negative control — aperture did not stay up without injection (exit $(val none_exit)); exit-3 is not specific to the death surfacing" >&2; tail -10 "$EVIDENCE_DIR/none.stderr.txt" >&2; exit 1; }
grep -qE "\"event\":\"readiness_changed\".*\"ready\":\"true\"" "$EVIDENCE_DIR/none.stderr.txt" \
    || { echo "FAIL: negative control — aperture never became ready" >&2; exit 1; }
grep -qE 'serve_loop_failed' "$EVIDENCE_DIR/none.stderr.txt" \
    && { echo "FAIL: negative control emitted serve_loop_failed without injection" >&2; exit 1; }

echo "OK — aperture surfaces a post-bind serving-loop death instead of a silent zombie: with APERTURE_TEST_INJECT_SERVE_FAILURE=grpc (and =http), aperture binds then emits event=serve_loop_failed transport=<t> (ERROR), flips readiness to false (reason=serve_loop_failed; /readyz -> sticky 503), and exits 3 — not a bound-but-dead zombie. Negative control: no injection -> aperture stays up and ready, no serve_loop_failed."
