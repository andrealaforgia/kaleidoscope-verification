#!/usr/bin/env bash
# QA04 — the LOAD-BEARING no-bearer-bypass test plus tenant isolation via the
# bearer, on the deployed query-api (read-path-query-api-auth-v0, ADR-0074
# DD3/R3). Strengthens QA02: here the binary runs WITH a valid env tenant AND
# that tenant's data is seeded, so a bypass would return REAL rows, not just a
# 200 against an empty store.
#
# Scenario:
#   1. gateway (KALEIDOSCOPE_DEFAULT_TENANT=tenant-a) ingests one `gen` metric;
#      SIGTERM flushes Pulse. Only tenant-a has data.
#   2. query-api on the SAME /data with auth CONFIGURED (audience
#      kaleidoscope-query, catalogue = {tenant-a, tenant-b}) AND
#      KALEIDOSCOPE_QUERY_TENANT=tenant-a (the env tenant DOES have data).
#   3. Probe /api/v1/query_range?query=gen:
#        - NO bearer       -> 401 AND zero rows. The load-bearing assertion:
#          auth-on must NOT fall through to the env tenant (tenant-a) even
#          though tenant-a has rows. A 200 with tenant-a's `gen` here is the
#          no-bearer-bypass (R3) bug.
#        - EXPIRED bearer  -> 401 AND zero rows (a present-but-invalid token
#          also must not fall through).
#        - tenant-a bearer -> 200 success, >=1 series (valid bearer reads the
#          token tenant's data; positive control).
#        - tenant-b bearer -> 200 success, 0 series (VALID token, but scopes to
#          tenant-b which has no data: the bearer's tenant governs scope, NOT
#          the env tenant — cross-tenant isolation via bearer).
#
# Transition-proof: RED (naming the breach) if the no-bearer or expired request
# returns ANY row, or if the tenant-b bearer can see tenant-a's `gen`.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

MINT="$HARNESS_DIR/mint-ingest-jwt.sh"
[[ -x "$MINT" ]] || { echo "FAIL: mint helper $MINT not executable" >&2; exit 1; }

cp "$HARNESS_DIR/jwt.secret" "$EVIDENCE_DIR/auth-secret"
# A two-tenant catalogue fixture (the harness default only has harness-tenant).
cat > "$EVIDENCE_DIR/auth-catalogue.toml" <<'TOML'
# QA04 two-tenant catalogue (aegis::load_catalogue).
[[tenants]]
id = "tenant-a"
display_name = "Tenant A"
[[tenants]]
id = "tenant-b"
display_name = "Tenant B"
TOML

TOK_A=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-a ROLE=viewer "$MINT")
TOK_B=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-b ROLE=viewer "$MINT")
TOK_EXPIRED=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-a ROLE=viewer TTL_SECS=-3600 "$MINT")
export TOK_A TOK_B TOK_EXPIRED

INLINE='
SHARED_DATA=$DATA_HOST/shared; mkdir -p "$SHARED_DATA"
GW_NAME="qa04-gw-$$"; QAPI_NAME="qa04-qapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 1. seed tenant-a data.
docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=tenant-a -e RUST_LOG=info -p 14330:4318 "$GW_IMAGE" > /dev/null
SAW=""; for _ in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14330 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 --otlp-attributes service.name=\"qa04-pilot\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" > /dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

# 2. query-api WITH auth + env tenant=tenant-a (which HAS data).
docker run --rm -d --name "$QAPI_NAME" -v "$SHARED_DATA:/data" \
    -v "'"$EVIDENCE_DIR"'/auth-secret:/auth/jwt.secret:ro" \
    -v "'"$EVIDENCE_DIR"'/auth-catalogue.toml:/auth/tenants.toml:ro" \
    -e KALEIDOSCOPE_QUERY_TENANT=tenant-a \
    -e KALEIDOSCOPE_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_QUERY_AUTH_SECRET_FILE=/auth/jwt.secret \
    -e KALEIDOSCOPE_QUERY_AUTH_CATALOGUE=/auth/tenants.toml \
    -e RUST_LOG=info -p 19105:9090 "$QAPI_IMAGE" > /dev/null
READY=""; for _ in $(seq 1 30); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19105/api/v1/query_range?query=gen" 2>/dev/null | grep -qE "^[0-9]{3}$" && { READY=yes; break; }
    sleep 1; done
[[ "$READY" == "yes" ]] || { echo "query-api never ready" >&2; docker logs "$QAPI_NAME" >&2 || true; exit 1; }
sleep 1

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
Q="query=gen&start=${START}&end=${END}&step=15s"
probe() { # $1 label  $2 bearer(empty=none)
    local out="'"$EVIDENCE_DIR"'/body-$1.json" code
    if [[ -n "$2" ]]; then
        code=$(curl -sS -o "$out" -w "%{http_code}" -H "Authorization: Bearer $2" "http://localhost:19105/api/v1/query_range?${Q}")
    else
        code=$(curl -sS -o "$out" -w "%{http_code}" "http://localhost:19105/api/v1/query_range?${Q}")
    fi
    echo "code_$1=$code rows_$1=$(jq -r ".data.result | length" "$out" 2>/dev/null || echo NA) status_$1=$(jq -r ".status // \"NA\"" "$out" 2>/dev/null)"
}
probe nobearer ""
probe expired  "$TOK_EXPIRED"
probe tenanta  "$TOK_A"
probe tenantb  "$TOK_B"
docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" QA04 "$INLINE"

OUT="$EVIDENCE_DIR/QA04.stdout.txt"
field() { grep -oE "$1_$2=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

# --- load-bearing: no-bearer must 401 with ZERO rows (no env-tenant fall-through) ---
[[ "$(field code nobearer)" == "401" ]] || fail "no-bearer: expected 401, got $(field code nobearer)"
RN=$(field rows nobearer); [[ "$RN" == "0" || "$RN" == "NA" ]] || fail "NO-BEARER RETURNED $RN ROWS — no-bearer-bypass (R3) BREACHED: auth-on query-api served the env tenant's seeded data without a bearer"
# --- expired token must also 401 with zero rows ---
[[ "$(field code expired)" == "401" ]] || fail "expired token: expected 401, got $(field code expired)"
RE=$(field rows expired); [[ "$RE" == "0" || "$RE" == "NA" ]] || fail "EXPIRED TOKEN RETURNED $RE ROWS — invalid bearer fell through to the env tenant"
echo "OK no-bearer -> 401, 0 rows; expired -> 401, 0 rows (no env-tenant fall-through despite tenant-a having data)"

# --- positive control: a valid tenant-a bearer reads tenant-a's data ---
[[ "$(field code tenanta)" == "200" ]] || fail "tenant-a bearer: expected 200, got $(field code tenanta)"
[[ "$(field status tenanta)" == "success" ]] || fail "tenant-a bearer: status not success"
RA=$(field rows tenanta); [[ "$RA" -ge 1 ]] || fail "tenant-a bearer returned $RA series; the seeded data is not readable via a valid bearer (precondition or scoping broken)"
echo "OK tenant-a bearer -> 200 success, $RA series (valid bearer reads the token tenant's data)"

# --- isolation: a VALID tenant-b bearer is scoped to tenant-b (no data), not the env tenant ---
[[ "$(field code tenantb)" == "200" ]] || fail "tenant-b bearer: expected 200 (valid token), got $(field code tenantb)"
[[ "$(field status tenantb)" == "success" ]] || fail "tenant-b bearer: status not success"
RB=$(field rows tenantb); [[ "$RB" == "0" ]] || fail "TENANT-B BEARER SAW $RB SERIES — cross-tenant leak: the bearer scoped to the env tenant (tenant-a) instead of the token tenant (tenant-b)"
echo "OK tenant-b bearer -> 200 success, 0 series (bearer scopes to tenant-b, isolating tenant-a's data)"

# --- redaction: no bearer substring in any body ---
for t in "$TOK_A" "$TOK_B" "$TOK_EXPIRED"; do
    if grep -rqF "$t" "$EVIDENCE_DIR"/body-*.json "$EVIDENCE_DIR/query-api.stderr.txt" 2>/dev/null; then
        fail "a bearer token substring leaked into a response body or the server log (redaction breach)"
    fi
done
echo "QA04 satisfied — no-bearer-bypass (R3) holds with env tenant + seeded data (401, 0 rows), invalid bearer no fall-through, valid bearer reads the TOKEN tenant, cross-tenant isolation via bearer holds, no token leak"
