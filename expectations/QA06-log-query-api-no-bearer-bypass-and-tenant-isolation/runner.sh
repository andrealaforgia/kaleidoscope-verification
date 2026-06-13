#!/usr/bin/env bash
# QA06 — the load-bearing no-bearer-bypass + tenant isolation on the deployed
# log-query-api (the logs analogue of QA04; read-path-query-api-auth-v0 R3,
# ADR-0074 DD3). Env tenant is SET and its logs are seeded, so a bypass would
# leak real records, not just 200 an empty store.
#
#   1. gateway (KALEIDOSCOPE_DEFAULT_TENANT=tenant-a) ingests logs with a known
#      body needle; only tenant-a has logs.
#   2. log-query-api on the same /data with auth CONFIGURED (audience
#      kaleidoscope-query, catalogue {tenant-a, tenant-b}) AND
#      KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-a (the env tenant HAS logs).
#   3. GET /api/v1/logs?...&body_contains=<needle>:
#        - NO bearer       -> 401 AND zero records (no fall-through to tenant-a).
#        - EXPIRED bearer  -> 401 AND zero records.
#        - tenant-a bearer -> 200 AND >=1 record (valid bearer reads the token
#          tenant's logs).
#        - tenant-b bearer -> 200 AND zero records (VALID token scoped to
#          tenant-b which has no logs: bearer governs scope, not the env tenant).
#
# Transition-proof: RED if no-bearer/expired returns ANY record, or if the
# tenant-b bearer sees tenant-a's needle.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

MINT="$HARNESS_DIR/mint-ingest-jwt.sh"
[[ -x "$MINT" ]] || { echo "FAIL: mint helper $MINT not executable" >&2; exit 1; }

cp "$HARNESS_DIR/jwt.secret" "$EVIDENCE_DIR/auth-secret"
cat > "$EVIDENCE_DIR/auth-catalogue.toml" <<'TOML'
[[tenants]]
id = "tenant-a"
display_name = "Tenant A"
[[tenants]]
id = "tenant-b"
display_name = "Tenant B"
TOML

NEEDLE="qa06-needle-ziggurat"
TOK_A=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-a ROLE=viewer "$MINT")
TOK_B=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-b ROLE=viewer "$MINT")
TOK_EXPIRED=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-a ROLE=viewer TTL_SECS=-3600 "$MINT")
export TOK_A TOK_B TOK_EXPIRED NEEDLE

INLINE='
SHARED_DATA=$DATA_HOST/shared; mkdir -p "$SHARED_DATA"
GW_NAME="qa06-gw-$$"; LQ_NAME="qa06-lq-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=tenant-a -e RUST_LOG=info -p 14331:4318 "$GW_IMAGE" > /dev/null
SAW=""; for _ in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    logs --otlp-endpoint localhost:14331 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 --body "'"$NEEDLE"'" --otlp-attributes service.name=\"qa06-pilot\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" > /dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$LQ_NAME" -v "$SHARED_DATA:/data" \
    -v "'"$EVIDENCE_DIR"'/auth-secret:/auth/jwt.secret:ro" \
    -v "'"$EVIDENCE_DIR"'/auth-catalogue.toml:/auth/tenants.toml:ro" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=tenant-a \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_SECRET_FILE=/auth/jwt.secret \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_CATALOGUE=/auth/tenants.toml \
    -e RUST_LOG=info -p 19094:9091 "$LQAPI_IMAGE" > /dev/null
READY=""; for _ in $(seq 1 30); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19094/api/v1/logs" 2>/dev/null | grep -qE "^[0-9]{3}$" && { READY=yes; break; }
    sleep 1; done
[[ "$READY" == "yes" ]] || { echo "log-query-api never ready" >&2; docker logs "$LQ_NAME" >&2 || true; exit 1; }
sleep 1

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
URL="http://localhost:19094/api/v1/logs?start=${START}&end=${END}&body_contains='"$NEEDLE"'"
probe() { # $1 label $2 bearer
    local out="'"$EVIDENCE_DIR"'/body-$1.json" code
    if [[ -n "$2" ]]; then code=$(curl -sS -o "$out" -w "%{http_code}" -H "Authorization: Bearer $2" "$URL");
    else code=$(curl -sS -o "$out" -w "%{http_code}" "$URL"); fi
    local n; n=$(jq -r "if type==\"array\" then length else 0 end" "$out" 2>/dev/null || echo NA)
    echo "code_$1=$code rows_$1=$n"
}
probe nobearer ""
probe expired  "$TOK_EXPIRED"
probe tenanta  "$TOK_A"
probe tenantb  "$TOK_B"
docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" QA06 "$INLINE"

OUT="$EVIDENCE_DIR/QA06.stdout.txt"
field() { grep -oE "$1_$2=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

[[ "$(field code nobearer)" == "401" ]] || fail "no-bearer: expected 401, got $(field code nobearer)"
RN=$(field rows nobearer); [[ "$RN" == "0" || "$RN" == "NA" ]] || fail "NO-BEARER RETURNED $RN LOG RECORDS — no-bearer-bypass (R3) BREACHED on the log API: served the env tenant's seeded logs without a bearer"
[[ "$(field code expired)" == "401" ]] || fail "expired: expected 401, got $(field code expired)"
RE=$(field rows expired); [[ "$RE" == "0" || "$RE" == "NA" ]] || fail "EXPIRED TOKEN RETURNED $RE LOG RECORDS — invalid bearer fell through to the env tenant on the log API"
echo "OK no-bearer -> 401, 0 records; expired -> 401, 0 records (no env-tenant fall-through on logs)"

[[ "$(field code tenanta)" == "200" ]] || fail "tenant-a bearer: expected 200, got $(field code tenanta)"
RA=$(field rows tenanta); [[ "$RA" -ge 1 ]] || fail "tenant-a bearer returned $RA records; the seeded logs are not readable via a valid bearer"
echo "OK tenant-a bearer -> 200, $RA records (valid bearer reads the token tenant's logs)"

[[ "$(field code tenantb)" == "200" ]] || fail "tenant-b bearer: expected 200 (valid token), got $(field code tenantb)"
RB=$(field rows tenantb); [[ "$RB" == "0" ]] || fail "TENANT-B BEARER SAW $RB RECORDS — cross-tenant leak on logs: bearer scoped to the env tenant (tenant-a) instead of the token tenant (tenant-b)"
echo "OK tenant-b bearer -> 200, 0 records (bearer scopes to tenant-b, isolating tenant-a's logs)"

echo "QA06 satisfied — log-query-api: no-bearer-bypass (R3) holds with env tenant + seeded logs, invalid bearer no fall-through, valid bearer reads the TOKEN tenant, cross-tenant isolation via bearer holds"
