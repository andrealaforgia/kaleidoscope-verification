#!/usr/bin/env bash
# A20 — with a valid ingest-auth config aperture STARTS and enforces the
# JWT at the door (ADR-0068 DD2, deliver 7f72db8):
#   - OTLP/HTTP ingest with NO bearer        -> 401 + WWW-Authenticate: Bearer
#   - OTLP/HTTP ingest with a BOGUS bearer    -> 401
#   - OTLP/HTTP ingest with a VALID HS256 JWT -> NOT 401 (door opens)
# Covers the enforcement half of UC-AUTH-002 (unauthenticated rejected).
#
# Self-contained (.no-compose): builds aperture from the HEAD snapshot,
# mounts a runner-written HS256 secret + tenant catalogue, runs aperture
# directly, crafts a valid token with the SAME secret, and curls the door.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a20-auth"
HPORT_HTTP=34518
HPORT_GRPC=34517
NAME="a20-auth-$$"
SECRET="a20-hs256-shared-secret-bytes-fixed"

echo "step 1: build aperture from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

# The HS256 secret: exact bytes, no trailing newline, shared between the
# mounted secret_file and the token we sign.
SECRET_FILE=$(mktemp -t a20-secret-XXXXXX)
printf '%s' "$SECRET" > "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE"; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "step 2: run aperture with a valid auth config" >&2
docker run -d --name "$NAME" \
    -p "${HPORT_HTTP}:4318" -p "${HPORT_GRPC}:4317" \
    -v "$EXP_DIR/auth-valid.toml:/etc/aperture/aperture.toml:ro" \
    -v "$EXP_DIR/tenants.toml:/etc/aperture/tenants.toml:ro" \
    -v "$SECRET_FILE:/etc/aperture/hs256.key:ro" \
    "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null

# Wait for the listener: a valid auth config MUST let aperture bind.
READY=0
for _ in $(seq 1 60); do
    if curl -sS --max-time 2 -o /dev/null -w '%{http_code}' "http://localhost:${HPORT_HTTP}/readyz" 2>/dev/null | grep -q '^200$'; then
        READY=1; break
    fi
    [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" != "true" ]] && break
    sleep 0.5
done
docker logs "$NAME" > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true
if (( READY == 0 )); then
    echo "FAIL — aperture did not bind /readyz=200 with a valid auth config" >&2
    tail -30 "$EVIDENCE_DIR/aperture.stderr.txt" >&2
    exit 1
fi

URL="http://localhost:${HPORT_HTTP}/v1/logs"
BODY='{"resourceLogs":[]}'

# 1. No bearer -> 401 + WWW-Authenticate: Bearer.
NOAUTH=$(curl -sS -D "$EVIDENCE_DIR/noauth.headers" -o "$EVIDENCE_DIR/noauth.body" -w '%{http_code}' \
    -H 'Content-Type: application/json' --data "$BODY" "$URL")
echo "noauth_code=$NOAUTH" | tee -a "$EVIDENCE_DIR/observation.txt"

# 2. Bogus bearer -> 401.
BOGUS=$(curl -sS -o "$EVIDENCE_DIR/bogus.body" -w '%{http_code}' \
    -H 'Content-Type: application/json' -H 'Authorization: Bearer not-a-real-token' \
    --data "$BODY" "$URL")
echo "bogus_code=$BOGUS" | tee -a "$EVIDENCE_DIR/observation.txt"

# 3. Valid HS256 JWT for a catalogued tenant -> NOT 401 (door opens).
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
HEADER='{"alg":"HS256","typ":"JWT"}'
EXP=$(( $(date -u +%s) + 86400 ))
PAYLOAD="{\"iss\":\"acme-observability\",\"aud\":\"kaleidoscope-ingest\",\"exp\":${EXP},\"tenant_id\":\"acme-prod\",\"kaleidoscope_role\":\"operator\"}"
H=$(printf '%s' "$HEADER"  | b64url)
P=$(printf '%s' "$PAYLOAD" | b64url)
SIG=$(printf '%s' "$H.$P" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)
JWT="$H.$P.$SIG"
echo "jwt=$JWT" > "$EVIDENCE_DIR/token.txt"
VALID=$(curl -sS -o "$EVIDENCE_DIR/valid.body" -w '%{http_code}' \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${JWT}" \
    --data "$BODY" "$URL")
echo "valid_code=$VALID" | tee -a "$EVIDENCE_DIR/observation.txt"

# Assertions.
[[ "$NOAUTH" == "401" ]] || { echo "FAIL — no-bearer ingest was not 401 (got $NOAUTH)" >&2; exit 1; }
grep -iqE '^WWW-Authenticate:\s*Bearer' "$EVIDENCE_DIR/noauth.headers" || { echo "FAIL — 401 lacked WWW-Authenticate: Bearer challenge" >&2; cat "$EVIDENCE_DIR/noauth.headers" >&2; exit 1; }
[[ "$BOGUS" == "401" ]] || { echo "FAIL — bogus-bearer ingest was not 401 (got $BOGUS)" >&2; exit 1; }
[[ "$VALID" != "401" ]] || { echo "FAIL — valid HS256 JWT was still rejected 401 (door did not open)" >&2; cat "$EVIDENCE_DIR/valid.body" >&2; exit 1; }
# The application/json door probe returns 415 once auth passes (the
# content-type gate, G03), proving auth is no longer the blocker. For a
# true 2xx ACCEPT, send real OTLP/protobuf with the bearer via
# telemetrygen, and confirm the SAME ingest WITHOUT the bearer is refused.
# telemetrygen wants the header value quoted: key="value".
HDR="Authorization=\"Bearer ${JWT}\""
TG=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0
ACCEPT_EXIT=0
docker run --rm --network host "$TG" logs \
    --otlp-endpoint "localhost:${HPORT_HTTP}" --otlp-insecure --otlp-http \
    --otlp-header "$HDR" --duration 1s --rate 1 \
    > "$EVIDENCE_DIR/tg-accept.out" 2>&1 || ACCEPT_EXIT=$?
echo "tg_accept_exit=$ACCEPT_EXIT" | tee -a "$EVIDENCE_DIR/observation.txt"
REJECT_EXIT=0
docker run --rm --network host "$TG" logs \
    --otlp-endpoint "localhost:${HPORT_HTTP}" --otlp-insecure --otlp-http \
    --duration 1s --rate 1 \
    > "$EVIDENCE_DIR/tg-reject.out" 2>&1 || REJECT_EXIT=$?
echo "tg_reject_exit=$REJECT_EXIT" | tee -a "$EVIDENCE_DIR/observation.txt"

[[ "$ACCEPT_EXIT" == "0" ]] || { echo "FAIL — OTLP/protobuf ingest WITH a valid bearer was not accepted (telemetrygen exit $ACCEPT_EXIT)" >&2; tail -20 "$EVIDENCE_DIR/tg-accept.out" >&2; exit 1; }
[[ "$REJECT_EXIT" != "0" ]] || { echo "FAIL — OTLP/protobuf ingest WITHOUT a bearer was accepted (should be 401)" >&2; tail -20 "$EVIDENCE_DIR/tg-reject.out" >&2; exit 1; }

echo "OK — unauthenticated ingest is 401 + WWW-Authenticate: Bearer (no bearer and bogus bearer); a valid HS256 JWT for a catalogued tenant clears the door (json probe $VALID), and a real OTLP/protobuf batch is ACCEPTED with the bearer (telemetrygen exit 0) but REFUSED without it"
