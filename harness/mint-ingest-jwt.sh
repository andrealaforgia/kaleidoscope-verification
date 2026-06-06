#!/usr/bin/env bash
# mint-ingest-jwt.sh — print a valid HS256 ingest JWT for the harness.
#
# Mandatory ingest auth (aegis-ingest-auth-v0, ADR-0068; see N29) means
# every OTLP request to the compose aperture must carry a bearer. This
# mints one signed with harness/jwt.secret (the same bytes mounted into
# the aperture container) and the harness claims, matching
# harness/aperture.toml's [aperture.security.auth.jwt] block and
# harness/tenants.toml.
#
# Output: the bare JWT on stdout (callers prepend "Bearer ").
# Env overrides: ISS, AUD, TENANT, ROLE, TTL_SECS.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRET_FILE="${SECRET_FILE:-$HARNESS_DIR/jwt.secret}"
[[ -r "$SECRET_FILE" ]] || { echo "mint-ingest-jwt: secret file $SECRET_FILE unreadable" >&2; exit 1; }
SECRET="$(cat "$SECRET_FILE")"

ISS="${ISS:-kaleidoscope-harness}"
AUD="${AUD:-kaleidoscope-cluster}"
TENANT="${TENANT:-harness-tenant}"
ROLE="${ROLE:-operator}"
TTL_SECS="${TTL_SECS:-86400}"
EXP=$(( $(date -u +%s) + TTL_SECS ))

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

HEADER='{"alg":"HS256","typ":"JWT"}'
PAYLOAD="{\"iss\":\"${ISS}\",\"aud\":\"${AUD}\",\"exp\":${EXP},\"tenant_id\":\"${TENANT}\",\"kaleidoscope_role\":\"${ROLE}\"}"
H=$(printf '%s' "$HEADER"  | b64url)
P=$(printf '%s' "$PAYLOAD" | b64url)
SIG=$(printf '%s' "$H.$P" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)
printf '%s.%s.%s' "$H" "$P" "$SIG"
