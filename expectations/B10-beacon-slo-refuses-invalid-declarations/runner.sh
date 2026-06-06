#!/usr/bin/env bash
# B10 — beacon REFUSES invalid [[slo]] declarations at load with the exact
# diagnostic, and NO always-fire rule reaches the catalogue (ADR-0067 F2/F3,
# the honesty guardrails on the SLO operator path). Complements B06 (the
# happy path).
#
# Three load-time refusals (each a rules dir holding only the bad [[slo]],
# so a refusal leaves zero rules and beacon "refuses to start", exit 1):
#  1. target_availability = 1.0 -> "invalid target_availability 1 (must be
#     strictly greater than 0 and strictly less than 1) in SLO ..." — a
#     degenerate always-fire rule is NEVER synthesised.
#  2. error_budget_period = "7d" -> "unsupported error_budget_period \"7d\"
#     (only \"30d\" is supported at v0) in SLO ...".
#  3. duplicate synthesised names (two [[slo]] same service) -> the
#     collision REFUSES the load and DROPS the colliding rules (never a
#     silent shadow); the diagnostic names the duplicate.
#
# Refused at LOAD, so no backend/mock and no 30s tick wait — fast.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/beacon-server:under-test"

echo "step 1: build beacon-server" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.beacon-server" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

# Run beacon against a (writable copy of a) rules dir; capture exit+stderr.
# $1=label  $2=fixture-subdir
run_case() {
    local label="$1"
    local fixture="$2"
    local name="b10-${label}-$$"
    local rh
    rh="$(mktemp -d -t b10-${label}-XXXXXX)"
    cp "$EXP_DIR/${fixture}/"*.toml "$rh/"
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" -e RUST_LOG=info -e NO_COLOR=1 \
        -v "$rh:/rules" \
        "$IMAGE" --rules /rules --backend "http://127.0.0.1:1/api/v1" >/dev/null 2>&1
    sleep 3
    local running exitc
    running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)
    exitc=$(docker inspect -f '{{.State.ExitCode}}' "$name" 2>/dev/null || echo NA)
    docker logs "$name" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/${label}.stderr.txt" || true
    echo "${label}_running=$running" | tee -a "$EVIDENCE_DIR/observation.txt"
    echo "${label}_exit=$exitc"      | tee -a "$EVIDENCE_DIR/observation.txt"
    docker rm -f "$name" >/dev/null 2>&1 || true
    rm -rf "$rh"
}

: > "$EVIDENCE_DIR/observation.txt"
run_case badtarget rules-badtarget
run_case badperiod rules-badperiod
run_case dup       rules-dup

OBS="$EVIDENCE_DIR/observation.txt"
exitof() { grep -oE "$1=[A-Za-z0-9]+" "$OBS" | tail -1 | cut -d= -f2; }

# Each bad declaration: a "rule load diagnostic" with the exact message,
# and beacon "refuses to start" (exit 1) since no valid rule survives — so
# NO synthesised rule (no always-fire footgun) reaches the catalogue.
refused() {
    local label="$1"; local err="$EVIDENCE_DIR/${label}.stderr.txt"
    grep -qE 'rule load diagnostic' "$err" || { echo "FAIL: ${label} — no rule load diagnostic" >&2; tail -10 "$err" >&2; exit 1; }
    grep -qE 'no rules loaded; refusing to start' "$err" || { echo "FAIL: ${label} — beacon did not refuse to start (a rule survived?)" >&2; tail -10 "$err" >&2; exit 1; }
    if grep -qE 'beacon\.reload\.succeeded|beacon-server starting rules_loaded=[1-9]' "$err"; then
        echo "FAIL: ${label} — beacon started with rules (the bad SLO synthesised a rule)" >&2; exit 1
    fi
}
refused badtarget
grep -qE "invalid target_availability" "$EVIDENCE_DIR/badtarget.stderr.txt" && grep -qE "must be strictly greater than 0 and strictly less than 1" "$EVIDENCE_DIR/badtarget.stderr.txt" \
    || { echo "FAIL: badtarget — diagnostic did not carry the exact invalid-target message" >&2; grep -i diagnostic "$EVIDENCE_DIR/badtarget.stderr.txt" >&2; exit 1; }

refused badperiod
grep -qE "unsupported error_budget_period" "$EVIDENCE_DIR/badperiod.stderr.txt" && grep -qE "only .30d. is supported at v0" "$EVIDENCE_DIR/badperiod.stderr.txt" \
    || { echo "FAIL: badperiod — diagnostic did not carry the exact unsupported-period message" >&2; grep -i diagnostic "$EVIDENCE_DIR/badperiod.stderr.txt" >&2; exit 1; }

refused dup
grep -qiE 'duplicate rule name' "$EVIDENCE_DIR/dup.stderr.txt" \
    || { echo "FAIL: dup — diagnostic did not name a duplicate rule" >&2; grep -i diagnostic "$EVIDENCE_DIR/dup.stderr.txt" >&2; exit 1; }

echo "OK — beacon refuses invalid [[slo]] declarations at load (no always-fire footgun): target_availability=1.0 -> 'invalid target_availability ... must be strictly greater than 0 and strictly less than 1'; error_budget_period=7d -> 'unsupported error_budget_period \"7d\" (only \"30d\")'; duplicate synthesised names -> the collision refuses+drops (diagnostic names the duplicate). Each leaves zero rules and beacon refuses to start (exit 1) — no degenerate rule reaches the catalogue. The SLO honesty guardrails (ADR-0067 F2/F3)."
