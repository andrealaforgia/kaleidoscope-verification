#!/usr/bin/env bash
# QA03 — read-path bearer auth is ENFORCED by the DEPLOYED log-query-api
# binary (read-path-query-api-auth-v0 slice 3b: log-query-api main.rs now
# resolves KALEIDOSCOPE_LOG_QUERY_AUTH_* and calls
# router_with_auth(store, tenant, auth); ADR-0074). The logs analogue of QA02.
#
# Boot the real log-query-api image with a complete read-auth config
# (issuer kaleidoscope-harness, audience kaleidoscope-query, the harness HS256
# secret, a catalogue holding `harness-tenant`) and NO env tenant, then hit
# GET /api/v1/logs over HTTP with the same adversarial bearer battery as QA02.
#
# Contract (query-http-common resolve_request_tenant_or_refuse, shared with
# query-api): a valid kaleidoscope-query bearer for a catalogued tenant is
# served 200; NO bearer -> 401 (no-bearer-bypass R3, no env-tenant
# fall-through); an ingest-audience token -> 401 (audience fence DD6); and the
# wrong-issuer / uncatalogued-tenant / unknown-role / expired / forged-sig /
# alg=none / malformed battery -> 401 each. The note this nails for slice 3b:
# the per-request auth is wired into the LOG binary's router, not just
# query-api's, and every log route is guarded.
#
# Transition-proof: RED (naming the breach) if any adversarial bearer — above
# all NO-bearer or the ingest-audience token — is served 200 on the log API.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

MINT="$HARNESS_DIR/mint-ingest-jwt.sh"
[[ -x "$MINT" ]] || { echo "FAIL: mint helper $MINT not executable" >&2; exit 1; }

cp "$HARNESS_DIR/jwt.secret" "$EVIDENCE_DIR/auth-secret"
cp "$HARNESS_DIR/tenants.toml" "$EVIDENCE_DIR/auth-catalogue.toml"
printf 'qa03-attacker-key-not-the-real-secret' > "$EVIDENCE_DIR/attacker-secret"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

TOK_VALID=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_INGEST=$(ISS=kaleidoscope-harness AUD=kaleidoscope-cluster TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_WRONGISS=$(ISS=evil-issuer AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_GHOST=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=ghost-tenant ROLE=viewer "$MINT")
TOK_BADROLE=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=intruder "$MINT")
TOK_EXPIRED=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer TTL_SECS=-3600 "$MINT")
TOK_WRONGKEY=$(SECRET_FILE="$EVIDENCE_DIR/attacker-secret" ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
last="${TOK_VALID: -1}"; rep=$([[ "$last" == "A" ]] && echo B || echo A)
TOK_FORGED="${TOK_VALID:0:${#TOK_VALID}-1}$rep"
EXP_FUT=$(( $(date -u +%s) + 3600 ))
NONE_H=$(printf '%s' '{"alg":"none","typ":"JWT"}' | b64url)
NONE_P=$(printf '%s' "{\"iss\":\"kaleidoscope-harness\",\"aud\":\"kaleidoscope-query\",\"exp\":${EXP_FUT},\"tenant_id\":\"harness-tenant\",\"kaleidoscope_role\":\"viewer\"}" | b64url)
TOK_ALGNONE="${NONE_H}.${NONE_P}."

export TOK_VALID TOK_INGEST TOK_WRONGISS TOK_GHOST TOK_BADROLE TOK_EXPIRED TOK_WRONGKEY TOK_FORGED TOK_ALGNONE

INLINE='
LQAPI_NAME="qa03-lqapi-$$"
cleanup() { docker stop --time 5 "$LQAPI_NAME" >/dev/null 2>&1 || true; docker rm "$LQAPI_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$LQAPI_NAME" \
    -v "$DATA_HOST:/data" \
    -v "'"$EVIDENCE_DIR"'/auth-secret:/auth/jwt.secret:ro" \
    -v "'"$EVIDENCE_DIR"'/auth-catalogue.toml:/auth/tenants.toml:ro" \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_SECRET_FILE=/auth/jwt.secret \
    -e KALEIDOSCOPE_LOG_QUERY_AUTH_CATALOGUE=/auth/tenants.toml \
    -e RUST_LOG=info \
    -p 19092:9091 "$LQAPI_IMAGE" > /dev/null

READY=""
for _ in $(seq 1 30); do
    if curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19092/api/v1/logs" 2>/dev/null | grep -qE "^[0-9]{3}$"; then READY=yes; break; fi
    docker logs "$LQAPI_NAME" 2>&1 | grep -q "listener_bound\|log_query_api_starting" && { READY=yes; break; }
    sleep 1
done
[[ "$READY" == "yes" ]] || { echo "log-query-api never became ready" >&2; docker logs "$LQAPI_NAME" >&2 || true; exit 1; }
sleep 1

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(date -u +%s)
probe() {
    local label="$1" bearer="$2" out="'"$EVIDENCE_DIR"'/body-$1.json" hdr="'"$EVIDENCE_DIR"'/hdr-$1.txt"
    local code base="http://localhost:19092/api/v1/logs?start=${START}&end=${END}&body_contains=qa03zz"
    if [[ -n "$bearer" ]]; then
        code=$(curl -sS -D "$hdr" -o "$out" -w "%{http_code}" -H "Authorization: Bearer $bearer" "$base")
    else
        code=$(curl -sS -D "$hdr" -o "$out" -w "%{http_code}" "$base")
    fi
    echo "code_${label}=${code}"
}

probe valid     "$TOK_VALID"
probe nobearer  ""
probe ingest    "$TOK_INGEST"
probe wrongiss  "$TOK_WRONGISS"
probe ghost     "$TOK_GHOST"
probe badrole   "$TOK_BADROLE"
probe expired   "$TOK_EXPIRED"
probe wrongkey  "$TOK_WRONGKEY"
probe forged    "$TOK_FORGED"
probe algnone   "$TOK_ALGNONE"
probe malformed "notajwt"

docker logs "$LQAPI_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-log-query-api.sh" "$EVIDENCE_DIR" QA03 "$INLINE"

OUT="$EVIDENCE_DIR/QA03.stdout.txt"
code() { grep -oE "code_$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; exit 1; }

CV=$(code valid)
[[ "$CV" == "200" ]] || { cat "$EVIDENCE_DIR/body-valid.json" >&2; fail "valid query-audience bearer was not served 200 (got $CV) on the log API"; }
jq -e 'type=="array" or .status=="success" or has("logs")' "$EVIDENCE_DIR/body-valid.json" >/dev/null 2>&1 \
    || { cat "$EVIDENCE_DIR/body-valid.json" >&2; fail "valid bearer: log body is not a success/array shape"; }
echo "OK valid -> 200 (log API serves an authorised query)"

CN=$(code nobearer)
[[ "$CN" != "200" ]] || { cat "$EVIDENCE_DIR/body-nobearer.json" >&2; fail "NO-BEARER REQUEST WAS SERVED 200 on the LOG API — no-bearer-bypass (R3) BREACHED"; }
[[ "$CN" == "401" ]] || fail "no bearer: expected 401, got $CN"
grep -qi '^WWW-Authenticate:[[:space:]]*Bearer' "$EVIDENCE_DIR/hdr-nobearer.txt" \
    || echo "WARN: no-bearer 401 lacks WWW-Authenticate: Bearer (RFC 6750); not failing on header alone"

CI=$(code ingest)
[[ "$CI" != "200" ]] || { cat "$EVIDENCE_DIR/body-ingest.json" >&2; fail "INGEST-AUDIENCE TOKEN WAS SERVED 200 on the LOG API — audience fence (DD6) BREACHED"; }
[[ "$CI" == "401" ]] || fail "ingest-audience token: expected 401, got $CI"
echo "OK no-bearer -> 401 (R3); ingest-audience -> 401 (audience fence) on the log API"

for c in wrongiss ghost badrole expired wrongkey forged algnone malformed; do
    cc=$(code "$c")
    [[ "$cc" == "401" ]] || { cat "$EVIDENCE_DIR/body-$c.json" >&2; fail "$c bearer: expected 401, got $cc"; }
done
echo "OK adversarial battery (wrongiss/ghost/badrole/expired/wrongkey/forged/algnone/malformed) -> 401 each"

if grep -rqi 'qa03-attacker-key\|BEGIN.*KEY' "$EVIDENCE_DIR"/body-*.json 2>/dev/null; then
    fail "a refusal body leaked secret-shaped material"
fi

echo "QA03 satisfied — deployed log-query-api enforces read-auth: valid query-audience bearer served, every adversarial bearer (incl no-bearer R3 and ingest-audience fence) refused 401, no env-tenant fall-through, no secret leak"
