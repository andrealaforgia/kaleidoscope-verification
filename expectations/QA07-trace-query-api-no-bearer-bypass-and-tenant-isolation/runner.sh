#!/usr/bin/env bash
# QA07 — the load-bearing no-bearer-bypass + tenant isolation on the deployed
# trace-query-api (the traces analogue of QA04/QA06; R3, ADR-0074 DD3). Env
# tenant SET and its traces seeded, so a bypass would leak real spans.
#
#   1. gateway (KALEIDOSCOPE_DEFAULT_TENANT=tenant-a) ingests traces for a known
#      service; only tenant-a has spans.
#   2. trace-query-api on the same /data with auth CONFIGURED (audience
#      kaleidoscope-query, catalogue {tenant-a, tenant-b}) AND
#      KALEIDOSCOPE_TRACE_QUERY_TENANT=tenant-a (the env tenant HAS spans).
#   3. GET /api/v1/traces?service=<svc>:
#        - NO bearer       -> 401 AND zero spans (no fall-through to tenant-a).
#        - EXPIRED bearer  -> 401 AND zero spans.
#        - tenant-a bearer -> 200 AND >=1 span (valid bearer reads the token
#          tenant's spans).
#        - tenant-b bearer -> 200 AND zero spans (VALID token scoped to
#          tenant-b which has no spans: bearer governs scope, not env tenant).
#
# Transition-proof: RED if no-bearer/expired returns ANY span, or if the
# tenant-b bearer sees tenant-a's spans.
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

SVC="qa07-pilot"
TOK_A=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-a ROLE=viewer "$MINT")
TOK_B=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-b ROLE=viewer "$MINT")
TOK_EXPIRED=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=tenant-a ROLE=viewer TTL_SECS=-3600 "$MINT")
export TOK_A TOK_B TOK_EXPIRED SVC

INLINE='
SHARED_DATA=$DATA_HOST/shared; mkdir -p "$SHARED_DATA"
GW_NAME="qa07-gw-$$"; TQ_NAME="qa07-tq-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=tenant-a -e RUST_LOG=info -p 14332:4318 "$GW_IMAGE" > /dev/null
SAW=""; for _ in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    traces --otlp-endpoint localhost:14332 --otlp-insecure --otlp-http \
    --traces 5 --child-spans 1 --service "'"$SVC"'" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" > /dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$TQ_NAME" -v "$SHARED_DATA:/data" \
    -v "'"$EVIDENCE_DIR"'/auth-secret:/auth/jwt.secret:ro" \
    -v "'"$EVIDENCE_DIR"'/auth-catalogue.toml:/auth/tenants.toml:ro" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=tenant-a \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_SECRET_FILE=/auth/jwt.secret \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_CATALOGUE=/auth/tenants.toml \
    -e RUST_LOG=info -p 19095:9092 "$TQAPI_IMAGE" > /dev/null
READY=""; for _ in $(seq 1 30); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19095/api/v1/traces" 2>/dev/null | grep -qE "^[0-9]{3}$" && { READY=yes; break; }
    sleep 1; done
[[ "$READY" == "yes" ]] || { echo "trace-query-api never ready" >&2; docker logs "$TQ_NAME" >&2 || true; exit 1; }
sleep 1

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
probe() { # $1 label $2 bearer
    local out="'"$EVIDENCE_DIR"'/body-$1.json" code
    if [[ -n "$2" ]]; then code=$(curl -sS -G -o "$out" -w "%{http_code}" -H "Authorization: Bearer $2" "http://localhost:19095/api/v1/traces" --data-urlencode "service='"$SVC"'" --data-urlencode "start=${START}" --data-urlencode "end=${END}");
    else code=$(curl -sS -G -o "$out" -w "%{http_code}" "http://localhost:19095/api/v1/traces" --data-urlencode "service='"$SVC"'" --data-urlencode "start=${START}" --data-urlencode "end=${END}"); fi
    local n; n=$(jq -r "if type==\"array\" then length else 0 end" "$out" 2>/dev/null || echo NA)
    echo "code_$1=$code rows_$1=$n"
}
probe nobearer ""
probe expired  "$TOK_EXPIRED"
probe tenanta  "$TOK_A"
probe tenantb  "$TOK_B"
docker logs "$TQ_NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" QA07 "$INLINE"

OUT="$EVIDENCE_DIR/QA07.stdout.txt"
field() { grep -oE "$1_$2=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

[[ "$(field code nobearer)" == "401" ]] || fail "no-bearer: expected 401, got $(field code nobearer)"
RN=$(field rows nobearer); [[ "$RN" == "0" || "$RN" == "NA" ]] || fail "NO-BEARER RETURNED $RN SPANS — no-bearer-bypass (R3) BREACHED on the trace API: served the env tenant's seeded spans without a bearer"
[[ "$(field code expired)" == "401" ]] || fail "expired: expected 401, got $(field code expired)"
RE=$(field rows expired); [[ "$RE" == "0" || "$RE" == "NA" ]] || fail "EXPIRED TOKEN RETURNED $RE SPANS — invalid bearer fell through to the env tenant on the trace API"
echo "OK no-bearer -> 401, 0 spans; expired -> 401, 0 spans (no env-tenant fall-through on traces)"

[[ "$(field code tenanta)" == "200" ]] || fail "tenant-a bearer: expected 200, got $(field code tenanta)"
RA=$(field rows tenanta); [[ "$RA" -ge 1 ]] || fail "tenant-a bearer returned $RA spans; the seeded traces are not readable via a valid bearer"
echo "OK tenant-a bearer -> 200, $RA spans (valid bearer reads the token tenant's spans)"

[[ "$(field code tenantb)" == "200" ]] || fail "tenant-b bearer: expected 200 (valid token), got $(field code tenantb)"
RB=$(field rows tenantb); [[ "$RB" == "0" ]] || fail "TENANT-B BEARER SAW $RB SPANS — cross-tenant leak on traces: bearer scoped to the env tenant (tenant-a) instead of the token tenant (tenant-b)"
echo "OK tenant-b bearer -> 200, 0 spans (bearer scopes to tenant-b, isolating tenant-a's spans)"

echo "QA07 satisfied — trace-query-api: no-bearer-bypass (R3) holds with env tenant + seeded spans, invalid bearer no fall-through, valid bearer reads the TOKEN tenant, cross-tenant isolation via bearer holds"
