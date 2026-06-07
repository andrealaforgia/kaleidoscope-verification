#!/usr/bin/env bash
# A21 — TRANSITION-PROOF. A fail-closed sink-probe refusal must SAY
# SOMETHING on stderr — it must not exit silently. aperture's forwarding
# sink runs a fail-closed Earned-Trust probe as the FIRST step of run(),
# BEFORE the tracing subscriber is installed; when the downstream is
# unreachable the probe refuses and the process exits non-zero, but at
# the current HEAD it does so with NO operator line (the error is logged
# through `tracing` which has no subscriber yet -> dropped). That is the
# honesty gap the implementer is closing in aperture-presubscriber-probe-
# stderr-v0.
#
# Contract asserted (the DESIRED behaviour, format-agnostic): the refusal
# exits non-zero AND emits a non-empty reason on stderr naming the
# failure. RED while the refusal is silent; flips GREEN unchanged once
# aperture prints a pre-subscriber stderr line on probe failure.
#
# Self-contained (.no-compose), A17/A19/A20 style.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a21-probe"
HPORT_HTTP=34818
HPORT_GRPC=34817
NAME="a21-probe-$$"
SECRET="a21-hs256-secret-bytes-fixed-value"

echo "step 1: build aperture from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

SECRET_FILE=$(mktemp -t a21-secret-XXXXXX)
printf '%s' "$SECRET" > "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE"; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "step 2: run aperture with a forwarding sink to an unreachable downstream" >&2
docker run -d --name "$NAME" \
    -p "${HPORT_HTTP}:4318" -p "${HPORT_GRPC}:4317" \
    -v "$EXP_DIR/aperture-forwarding-unreachable.toml:/etc/aperture/aperture.toml:ro" \
    -v "$EXP_DIR/tenants.toml:/etc/aperture/tenants.toml:ro" \
    -v "$SECRET_FILE:/etc/aperture/hs256.key:ro" \
    "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null

# Observe up to a deadline: the probe should refuse (process exits) and
# never bind a listener.
READYZ=000 RUNNING=true
for _ in $(seq 1 40); do
    RUNNING=$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)
    READYZ=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' "http://localhost:${HPORT_HTTP}/readyz" 2>/dev/null) || true
    [[ -z "$READYZ" ]] && READYZ=000
    [[ "$READYZ" == "200" ]] && break
    [[ "$RUNNING" != "true" ]] && break
    sleep 0.5
done
EXITCODE=$(docker inspect -f '{{.State.ExitCode}}' "$NAME" 2>/dev/null || echo NA)
docker logs "$NAME" > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

STDERR_BYTES=$(wc -c < "$EVIDENCE_DIR/aperture.stderr.txt" | tr -d ' ')
echo "readyz=$READYZ running=$RUNNING exitcode=$EXITCODE stderr_bytes=$STDERR_BYTES" | tee "$EVIDENCE_DIR/observation.txt"

# It must NOT have bound a plaintext listener (fail-closed).
[[ "$READYZ" == "200" ]] && { echo "aperture bound /readyz=200 despite an unreachable forwarding downstream (probe should refuse)" >&2; exit 1; }
# It must have exited non-zero (the refusal).
[[ "$EXITCODE" =~ ^[1-9][0-9]*$ ]] || { echo "aperture did not exit non-zero on probe failure (exit=$EXITCODE)" >&2; tail -20 "$EVIDENCE_DIR/aperture.stderr.txt" >&2; exit 1; }
# The contract: the refusal SAYS SOMETHING — a non-empty reason on stderr
# naming the probe/sink/refusal. RED while silent.
if [[ "$STDERR_BYTES" -gt 0 ]] && grep -qiE 'probe|sink|refus|health\.startup|downstream|unreachable|earned.?trust|192\.0\.2\.1' "$EVIDENCE_DIR/aperture.stderr.txt"; then
    echo "OK (GREEN) — the fail-closed probe refusal emits a reason on stderr (exit ${EXITCODE}, no listener); the refusal is no longer silent"
    exit 0
fi
echo "RED — the probe refusal is SILENT: exit ${EXITCODE}, no listener, but stderr carries no reason (${STDERR_BYTES} bytes). Grounds aperture-presubscriber-probe-stderr-v0 (the pre-subscriber probe failure is dropped because tracing has no subscriber yet). Flips GREEN when aperture prints a refusal line." >&2
exit 1
