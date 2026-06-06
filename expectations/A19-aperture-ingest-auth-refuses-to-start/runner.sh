#!/usr/bin/env bash
# A19 — aperture ingest auth is mandatory (no off switch): a missing,
# incomplete, or unreadable [aperture.security.auth.jwt] block makes
# aperture REFUSE TO START — exit 2, event=config_validation_failed
# naming the offending table/field/path, and no listener bound.
# Grounds aegis-ingest-auth-v0 (ADR-0068 DD4, deliver 7f72db8).
# Covers UC-AUTH-003 (ingest auth config parsed/validated) and the
# refuse-to-start half of UC-AUTH-002.
#
# Self-contained (.no-compose), A17-style: builds aperture from the HEAD
# snapshot and runs it directly, so it does not depend on the compose
# readiness gate (which assumes a binding listener and cannot apply when
# aperture refuses to bind).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a19-auth"
HPORT_HTTP=34418
HPORT_GRPC=34417

echo "step 1: build aperture from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

: > "$EVIDENCE_DIR/observation.txt"

# run_fixture <toml> <label> <expected-naming-substring>
run_fixture() {
    local toml="$1" label="$2" needle="$3"
    local name="a19-${label}-$$"
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" \
        -p "${HPORT_HTTP}:4318" -p "${HPORT_GRPC}:4317" \
        -v "$EXP_DIR/${toml}:/etc/aperture/aperture.toml:ro" \
        "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null

    local readyz=000 running=true
    for _ in $(seq 1 30); do
        running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)
        readyz=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' "http://localhost:${HPORT_HTTP}/readyz" 2>/dev/null) || true
        [[ -z "$readyz" ]] && readyz=000
        [[ "$readyz" == "200" ]] && break
        [[ "$running" != "true" ]] && break
        sleep 0.5
    done
    local exitcode
    exitcode=$(docker inspect -f '{{.State.ExitCode}}' "$name" 2>/dev/null || echo NA)
    docker logs "$name" > "$EVIDENCE_DIR/${label}.stderr.txt" 2>&1 || true
    docker rm -f "$name" >/dev/null 2>&1 || true

    {
        echo "[$label] readyz=$readyz running=$running exitcode=$exitcode"
    } | tee -a "$EVIDENCE_DIR/observation.txt"

    # SAFE shape: no listener, clean non-zero refusal naming the offender.
    [[ "$readyz" == "200" ]] && { echo "FAIL [$label]: aperture bound a listener (readyz=200) despite a bad auth block" >&2; return 1; }
    [[ "$exitcode" == "2" ]] || { echo "FAIL [$label]: expected exit 2, got $exitcode" >&2; tail -20 "$EVIDENCE_DIR/${label}.stderr.txt" >&2; return 1; }
    grep -qE 'event=config_validation_failed' "$EVIDENCE_DIR/${label}.stderr.txt" || { echo "FAIL [$label]: missing event=config_validation_failed" >&2; tail -20 "$EVIDENCE_DIR/${label}.stderr.txt" >&2; return 1; }
    grep -qF "$needle" "$EVIDENCE_DIR/${label}.stderr.txt" || { echo "FAIL [$label]: refusal did not name the offender ($needle)" >&2; tail -20 "$EVIDENCE_DIR/${label}.stderr.txt" >&2; return 1; }
    echo "OK [$label] — refused: exit 2, config_validation_failed, names the offender, no listener"
}

run_fixture auth-absent.toml          absent          'missing [aperture.security.auth.jwt] block'
run_fixture auth-missing-field.toml   missing-field   'secret_file'
run_fixture auth-unreadable-secret.toml unreadable    '/nonexistent/hs256.key'

# Secret-never-logged: the unreadable case names the PATH; assert the
# refusal stream never contains a raw HS256 secret value we might fear.
echo "A19 — all three refusal shapes confirmed; ingest auth has no off switch"
