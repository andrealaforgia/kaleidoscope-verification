#!/usr/bin/env bash
# A22 — ADVERSARIAL auth negative-space. A20 proved no-token / junk-string
# reject and a valid token accepts; this attacks the door with WELL-FORMED
# but illegitimate HS256 JWTs and asserts aperture (aegis validator)
# rejects every one with 401:
#   - expired (exp in the past)              -> Expired
#   - alg=none (no signature)                -> algorithm not allowed
#   - forged signature (wrong HMAC key)      -> InvalidSignature
#   - tenant_id not in the catalogue         -> UnknownTenant
#   - wrong issuer / wrong audience          -> WrongIssuer / WrongAudience
#   - unknown role (not viewer/operator)     -> UnknownRole
# A genuinely valid token is the positive control (door opens -> 415 at
# the content-type gate). Any 2xx/415 on a forged token would be an auth
# BYPASS. These are the security-critical regression guards that catch a
# future weakening of the validator (e.g. accidentally accepting alg=none).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a22-auth"
HPORT_HTTP=34922
HPORT_GRPC=34921
NAME="a22-auth-$$"
SECRET="a22-hs256-shared-secret-bytes-fixed"

echo "step 1: build aperture from snapshot" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

SECRET_FILE=$(mktemp -t a22-secret-XXXXXX)
printf '%s' "$SECRET" > "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE"; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" \
    -p "${HPORT_HTTP}:4318" -p "${HPORT_GRPC}:4317" \
    -v "$EXP_DIR/auth-valid.toml:/etc/aperture/aperture.toml:ro" \
    -v "$EXP_DIR/tenants.toml:/etc/aperture/tenants.toml:ro" \
    -v "$SECRET_FILE:/etc/aperture/hs256.key:ro" \
    "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null
READY=0
for _ in $(seq 1 60); do
    curl -sS --max-time 2 -o /dev/null "http://localhost:${HPORT_HTTP}/readyz" 2>/dev/null && { READY=1; break; }
    [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" != "true" ]] && break
    sleep 0.5
done
(( READY == 1 )) || { echo "aperture did not bind with valid auth" >&2; docker logs "$NAME" >&2 2>&1 | tail; exit 1; }

b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
mk() { # $1=header_json $2=payload_json $3=secret|NONE -> jwt
    local h p s; h=$(printf '%s' "$1" | b64); p=$(printf '%s' "$2" | b64)
    if [[ "$3" == "NONE" ]]; then printf '%s.%s.' "$h" "$p"
    else s=$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$3" -binary | b64); printf '%s.%s.%s' "$h" "$p" "$s"; fi
}
hit() { curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $1" --data '{"resourceLogs":[]}' "http://localhost:${HPORT_HTTP}/v1/logs"; }
NOW=$(date -u +%s); FUT=$((NOW + 86400)); PAST=$((NOW - 3600))
HJWT='{"alg":"HS256","typ":"JWT"}'; HNONE='{"alg":"none","typ":"JWT"}'
ISS="acme-observability"; AUD="kaleidoscope-ingest"
# Build each claim set as a variable (NOT inline in a nested echo "$(...)"
# — the comma/quote-laden JSON mangles under deep command-substitution).
clm() { printf '{"iss":"%s","aud":"%s","exp":%s,"tenant_id":"%s","kaleidoscope_role":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
TOK_baseline=$(mk "$HJWT"  "$(clm "$ISS" "$AUD" "$FUT"  acme-prod   operator)"  "$SECRET")
TOK_expired=$(mk  "$HJWT"  "$(clm "$ISS" "$AUD" "$PAST" acme-prod   operator)"  "$SECRET")
TOK_algnone=$(mk  "$HNONE" "$(clm "$ISS" "$AUD" "$FUT"  acme-prod   operator)"  NONE)
TOK_forgedsig=$(mk "$HJWT" "$(clm "$ISS" "$AUD" "$FUT"  acme-prod   operator)"  attacker-wrong-key)
TOK_uncatalogued=$(mk "$HJWT" "$(clm "$ISS" "$AUD" "$FUT" globex-evil operator)" "$SECRET")
TOK_wrongiss=$(mk "$HJWT"  "$(clm evil    "$AUD" "$FUT"  acme-prod   operator)"  "$SECRET")
TOK_wrongaud=$(mk "$HJWT"  "$(clm "$ISS"  evil   "$FUT"  acme-prod   operator)"  "$SECRET")
TOK_unknownrole=$(mk "$HJWT" "$(clm "$ISS" "$AUD" "$FUT" acme-prod   superadmin)" "$SECRET")
{
  for k in baseline expired algnone forgedsig uncatalogued wrongiss wrongaud unknownrole; do
    eval "tok=\$TOK_$k"
    echo "$k=$(hit "$tok")"
  done
} | tee "$EVIDENCE_DIR/codes.txt"
docker logs "$NAME" > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

val() { grep -oE "^$1=[0-9]+" "$EVIDENCE_DIR/codes.txt" | tail -1 | cut -d= -f2; }
# Positive control: the valid token clears auth (NOT 401).
[[ "$(val baseline)" != "401" ]] || { echo "control failed: a VALID token was 401'd ($(val baseline)) — harness/secret mismatch" >&2; exit 1; }
# Every forged token must be 401. A 2xx/415 is an auth BYPASS.
for k in expired algnone forgedsig uncatalogued wrongiss wrongaud unknownrole; do
    c="$(val "$k")"
    [[ "$c" == "401" ]] || { echo "AUTH BYPASS — forged token '$k' was NOT rejected (got $c, expected 401)" >&2; exit 1; }
done
echo "OK — every forged HS256 token is rejected 401 (expired, alg=none, forged-sig, uncatalogued-tenant, wrong-iss, wrong-aud, unknown-role); a valid token clears the door ($(val baseline)). No auth bypass."
