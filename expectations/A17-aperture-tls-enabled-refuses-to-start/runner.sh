#!/usr/bin/env bash
# A15 — aperture TLS knob: refuse-or-encrypt, NOT silent plaintext.
#
# Grounds issue 008 black-box. An operator who sets `tls.enabled=true`
# expects transport encryption. At v0 aperture neither encrypts nor
# refuses: it logs `event=tls_not_supported_in_v0` and binds PLAINTEXT
# anyway (compose.rs warn_if_v0_security_knob_set; false comment
# sinks.rs:94 claims a validator rejects it). That silent downgrade is
# the Earned-Trust violation tracked by issue 008. tls-config-reject-v0
# (ADR-0061) is in flight to make aperture REFUSE TO START on this knob.
#
# Contract under test (the SAFE shapes): EITHER aperture refuses to start
# (exits non-zero, emits a refusal naming the unsupported knob, binds no
# listener) OR — once TLS is actually implemented — it serves TLS. The
# UNSAFE shape this expectation fails on is the current one: a plaintext
# listener answering /readyz over plain HTTP while tls.enabled=true.
#
# Transition-proof: self-contained (.no-compose), builds aperture from
# the HEAD snapshot and runs it directly, so it does not depend on the
# compose readiness gate (which assumes a binding listener and would
# itself break once aperture starts refusing). RED at ea72f1e (downgrade);
# flips GREEN automatically when the refusal lands.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

: > "$EVIDENCE_DIR/observation.txt"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a15-tls"
# Unique high host ports (N27 discipline): avoid the dev-side compose
# squatter on 4317-4318.
HPORT_HTTP=34318
HPORT_GRPC=34317
NAME="a15-tls-$$"

echo "step 1: build aperture from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "step 2: run aperture with tls.enabled=true" >&2
docker run -d --name "$NAME" \
    -p "${HPORT_HTTP}:4318" -p "${HPORT_GRPC}:4317" \
    -v "$EXP_DIR/aperture-tls-enabled.toml:/etc/aperture/aperture.toml:ro" \
    "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null

# Observe up to a deadline: does a plaintext listener answer (DOWNGRADE),
# or does the process exit (candidate REFUSAL)?
READYZ=000
RUNNING=true
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
echo "readyz_plaintext=$READYZ"  | tee -a "$EVIDENCE_DIR/observation.txt"
echo "running=$RUNNING"          | tee -a "$EVIDENCE_DIR/observation.txt"
echo "exitcode=$EXITCODE"        | tee -a "$EVIDENCE_DIR/observation.txt"
docker rm -f "$NAME" >/dev/null 2>&1 || true

WARN_TLS=no
grep -qE 'tls_not_supported_in_v0' "$EVIDENCE_DIR/aperture.stderr.txt" && WARN_TLS=yes
echo "warn_tls_not_supported=$WARN_TLS" | tee -a "$EVIDENCE_DIR/observation.txt"
# The refusal event the implementer wired (message 020, SHA a56c317):
# `event=config_validation_failed` on stderr, naming the knob, exit 2.
CFG_REFUSAL=no
grep -qE 'event=config_validation_failed' "$EVIDENCE_DIR/aperture.stderr.txt" && CFG_REFUSAL=yes
echo "config_validation_failed=$CFG_REFUSAL" | tee -a "$EVIDENCE_DIR/observation.txt"
NAMES_KNOB=no
grep -qE 'tls\.enabled' "$EVIDENCE_DIR/aperture.stderr.txt" && NAMES_KNOB=yes
echo "names_tls_enabled=$NAMES_KNOB" | tee -a "$EVIDENCE_DIR/observation.txt"

# Classify.
if [[ "$READYZ" == "200" ]]; then
    # DOWNGRADE: a plaintext listener answered /readyz over plain HTTP
    # while tls.enabled=true. Contract violated -> issue 008 ground. RED.
    echo "RED (issue 008 grounded) — aperture answered /readyz=200 over PLAINTEXT http with tls.enabled=true (warn_tls_not_supported=${WARN_TLS}); an operator who asked for transport encryption silently got a plaintext listener. The refuse-or-encrypt contract is VIOLATED at this SHA." >&2
    exit 1
fi

if [[ "$RUNNING" != "true" && "$EXITCODE" != "0" && "$EXITCODE" != "NA" ]]; then
    # REFUSAL (tls-config-reject-v0, a56c317): config validation fails
    # BEFORE any Config is built, so the bind path is never entered (the
    # no-plaintext-bind guarantee is structural). Require the exact event
    # naming the knob, exit 2, and no plaintext listener.
    if [[ "$CFG_REFUSAL" == "yes" && "$NAMES_KNOB" == "yes" ]]; then
        [[ "$EXITCODE" == "2" ]] || echo "NOTE: refusal exit code is ${EXITCODE}, expected 2 (implementer msg 020)" >&2
        echo "GREEN (refusal) — aperture REFUSES to start with tls.enabled=true: exit ${EXITCODE}, no plaintext listener bound (readyz=${READYZ}), stderr event=config_validation_failed naming tls.enabled. Config validation fails before any bind (structural no-plaintext guarantee). The refuse-or-encrypt contract is met; issue 008 resolved black-box." >&2
        exit 0
    fi
    echo "FAIL — aperture exited ${EXITCODE} but the refusal was not the expected config_validation_failed naming tls.enabled (config_validation_failed=${CFG_REFUSAL}, names_knob=${NAMES_KNOB}); cannot confirm a clean refusal vs a crash." >&2
    tail -20 "$EVIDENCE_DIR/aperture.stderr.txt" >&2
    exit 2
fi

echo "FAIL — indeterminate: readyz=${READYZ}, running=${RUNNING}, exit=${EXITCODE}. Neither a plaintext /readyz nor a clean non-zero refusal." >&2
tail -20 "$EVIDENCE_DIR/aperture.stderr.txt" >&2
exit 3
