#!/usr/bin/env bash
# A24 — TRANSITION-PROOF (currently RED). aperture-body-size-cap-v0 exists to
# wire the "disclosed-but-unwired" max_recv_msg_size knob: ADR-0073 (Earned-
# Trust note) "an operator who sets it, expecting OOM protection, gets none",
# and the Decision (line 67) wires it — "into_config reads the value from the
# gRPC arm when set ... exactly as concurrency does" — with line 121 claiming
# "the disclosed-but-unwired max_recv_msg_size knob now delivers the OOM
# protection an operator assumes".
#
# This expectation asserts that OBSERVABLE contract: a max_recv_msg_size set in
# the TOML config is HONOURED on the HTTP ingest path.
#
# DESIRED (GREEN): with max_recv_msg_size = 16384 (16 KiB) configured, a 100 KiB
#   POST /v1/logs is refused 413 (over the configured cap; under the 2 MiB
#   framework default, so a 413 here can ONLY come from the configured cap).
# OBSERVED today (RED): 100 KiB -> 400 (accepted past the size gate; only the
#   2 MiB default applies). into_config (config/mod.rs:645+) never calls
#   .max_recv_msg_size(), unlike max_concurrent_requests one line over, so the
#   configured cap is unwired and ignored on every TOML deployment. The cap is
#   reachable only via Config::builder() (in-process slice_11 tests).
# Pairs with A23 (the unset/default path, GREEN since 88ef2aa). A24 is the
# remaining, distinct config-reachability facet of issue 014.
set -uo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
IMAGE="kaleidoscope-expectations/aperture:a24-cap16k"
HPORT_HTTP=34826
NAME="a24-cap16k-$$"
SECRET="a24-hs256-shared-secret-fixed-bytes"
ISS="acme-observability"; AUD="kaleidoscope-ingest"

echo "step 1: build aperture from snapshot (HEAD)" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.aperture" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

SECRET_FILE=$(mktemp -t a24-secret-XXXXXX); printf '%s' "$SECRET" > "$SECRET_FILE"
trap 'rm -f "$SECRET_FILE" /tmp/a24-body.$$ ; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "${HPORT_HTTP}:4318" \
    -v "$EXP_DIR/auth-cap16k.toml:/etc/aperture/aperture.toml:ro" \
    -v "$EXP_DIR/tenants.toml:/etc/aperture/tenants.toml:ro" \
    -v "$SECRET_FILE:/etc/aperture/hs256.key:ro" \
    "$IMAGE" --config /etc/aperture/aperture.toml >/dev/null
READY=0
for _ in $(seq 1 60); do
    curl -sS --max-time 2 -o /dev/null "http://localhost:${HPORT_HTTP}/readyz" 2>/dev/null && { READY=1; break; }
    [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" != "true" ]] && break
    sleep 0.5
done
(( READY == 1 )) || { echo "aperture did not bind with the configured-cap config" >&2; docker logs "$NAME" >&2 2>&1 | tail; exit 1; }

b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
mk() { local h p s; h=$(printf '%s' "$1" | b64); p=$(printf '%s' "$2" | b64)
       s=$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$3" -binary | b64)
       printf '%s.%s.%s' "$h" "$p" "$s"; }
clm() { printf '{"iss":"%s","aud":"%s","exp":%s,"tenant_id":"%s","kaleidoscope_role":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
NOW=$(date -u +%s); FUT=$((NOW + 86400))
TOK=$(mk '{"alg":"HS256","typ":"JWT"}' "$(clm "$ISS" "$AUD" "$FUT" acme-prod operator)" "$SECRET")

post() { head -c "$1" /dev/zero | tr '\0' 'A' > "/tmp/a24-body.$$"
    curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
        -H 'Content-Type: application/x-protobuf' -H "Authorization: Bearer $TOK" \
        --data-binary @"/tmp/a24-body.$$" "http://localhost:${HPORT_HTTP}/v1/logs" 2>/dev/null; }
C_1KB=$(post 1024)      # under the 16 KiB configured cap -> non-413 either way
C_100KB=$(post 102400)  # over 16 KiB cap, under 2 MiB default -> MUST be 413 iff the configured cap is wired
{
  echo "body_1KB=$C_1KB"
  echo "body_100KB=$C_100KB"
} | tee "$EVIDENCE_DIR/codes.txt"
docker logs "$NAME" > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true

# Control: the 1 KiB body must clear auth + content-type (NOT 401/415) so the
# 100 KiB verdict is attributable to the configured cap alone.
[[ "$C_1KB" != "401" && "$C_1KB" != "415" ]] || { echo "control failed: 1 KiB baseline was $C_1KB (auth/content-type)" >&2; exit 1; }
# DESIRED contract: a TOML-configured 16 KiB cap refuses a 100 KiB body.
if [[ "$C_100KB" == "413" ]]; then
    echo "OK — a TOML-configured max_recv_msg_size=16384 refuses a 100 KiB body (413). The knob is wired. A24 GREEN."
    exit 0
fi
echo "RED — TOML max_recv_msg_size=16384 IGNORED: a 100 KiB body got $C_100KB (expected 413). into_config never wires the cap (unlike max_concurrent_requests), so only the 2 MiB default applies; the operator's configured cap does nothing — the very 'disclosed-but-unwired knob, operator gets none' that ADR-0073 (lines 8/67/121) says this feature closes." >&2
exit 1
