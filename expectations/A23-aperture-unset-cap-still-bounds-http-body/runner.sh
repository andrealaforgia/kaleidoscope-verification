#!/usr/bin/env bash
# A23 — TRANSITION-PROOF (currently RED). aperture-body-size-cap-v0 moved the
# HTTP ingest handlers from the buffered `axum::body::Bytes` extractor (which
# carries axum's built-in 2 MiB `DefaultBodyLimit`) to a streaming `Body`.
# The feature's own design decision DD2/C2 (body_size_cap.rs:6-7,100,135-137)
# states the unset / no-cap path is "byte-for-byte today's behaviour" and
# "mirrors axum's default Bytes extraction". This expectation asserts that
# OBSERVABLE contract: with NO cap configured, an oversized HTTP OTLP body is
# REFUSED (413) before being fully buffered, exactly as the pre-feature binary
# refused it.
#
# DESIRED (GREEN): a 20 MiB POST /v1/logs (valid bearer, correct content-type)
#   is refused 413 (the no-cap path bounds the body as it did before).
# OBSERVED today (RED): the no-cap path dropped the 2 MiB DefaultBodyLimit, so
#   the 20 MiB body is accepted past the size gate and FULLY BUFFERED, reaching
#   protobuf decode -> 400. Differential proof at delivery: pre-feature parent
#   ad8436d returns 413 for the same body; HEAD returns 400.
# Format-agnostic: flips GREEN whether the fix restores a default bound on the
# no-cap path or wires a TOML cap that is honoured — either way 20 MiB -> 413.
set -uo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a23-nocap"
HPORT_HTTP=34823
NAME="a23-nocap-$$"
SECRET="a23-hs256-shared-secret-fixed-bytes"
ISS="acme-observability"; AUD="kaleidoscope-ingest"

echo "step 1: build aperture from snapshot (HEAD)" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

SECRET_FILE=$(mktemp -t a23-secret-XXXXXX); printf '%s' "$SECRET" > "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE" /tmp/a23-body.$$ ; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "${HPORT_HTTP}:4318" \
    -v "$EXP_DIR/auth-nocap.toml:/etc/aperture/aperture.toml:ro" \
    -v "$EXP_DIR/tenants.toml:/etc/aperture/tenants.toml:ro" \
    -v "$SECRET_FILE:/etc/aperture/hs256.key:ro" \
    "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null
READY=0
for _ in $(seq 1 60); do
    curl -sS --max-time 2 -o /dev/null "http://localhost:${HPORT_HTTP}/readyz" 2>/dev/null && { READY=1; break; }
    [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" != "true" ]] && break
    sleep 0.5
done
(( READY == 1 )) || { echo "aperture did not bind with the no-cap auth config" >&2; docker logs "$NAME" >&2 2>&1 | tail; exit 1; }

b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
mk() { local h p s; h=$(printf '%s' "$1" | b64); p=$(printf '%s' "$2" | b64)
       s=$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$3" -binary | b64)
       printf '%s.%s.%s' "$h" "$p" "$s"; }
clm() { printf '{"iss":"%s","aud":"%s","exp":%s,"tenant_id":"%s","kaleidoscope_role":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
NOW=$(date -u +%s); FUT=$((NOW + 86400))
TOK=$(mk '{"alg":"HS256","typ":"JWT"}' "$(clm "$ISS" "$AUD" "$FUT" acme-prod operator)" "$SECRET")

post() { # $1=byte count -> http code; body is filler (auth+content-type pass; size is the only variable)
    head -c "$1" /dev/zero | tr '\0' 'A' > "/tmp/a23-body.$$"
    curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
        -H 'Content-Type: application/x-protobuf' -H "Authorization: Bearer $TOK" \
        --data-binary @"/tmp/a23-body.$$" "http://localhost:${HPORT_HTTP}/v1/logs" 2>/dev/null
}
C_SMALL=$(post 100)        # baseline: auth+content-type pass, malformed protobuf -> 400
C_20MB=$(post 20971520)    # 20 MiB: must be refused (413) on the no-cap path
{
  echo "small_100B=$C_SMALL"
  echo "body_20MB=$C_20MB"
} | tee "$EVIDENCE_DIR/codes.txt"
docker logs "$NAME" > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true

# Control: the 100 B baseline must clear auth + content-type (NOT 401/415), so a
# differing 20 MiB verdict is attributable to body SIZE alone.
[[ "$C_SMALL" != "401" && "$C_SMALL" != "415" ]] || { echo "control failed: 100 B baseline was $C_SMALL (auth/content-type), cannot isolate size" >&2; exit 1; }
# DESIRED contract (DD2/C2): the no-cap path bounds an oversized body.
if [[ "$C_20MB" == "413" ]]; then
    echo "OK — no-cap path refuses a 20 MiB body (413); DD2/C2 'byte-for-byte today' holds. A23 GREEN."
    exit 0
fi
echo "RED — no-cap path ACCEPTED a 20 MiB body (got $C_20MB, expected 413). The streaming-Body refactor dropped axum's 2 MiB DefaultBodyLimit; DD2/C2 'unset = today's behaviour' is violated, the body is fully buffered, and into_config wires no TOML cap to restore the bound. Pre-feature parent ad8436d refuses the same body 413." >&2
exit 1
