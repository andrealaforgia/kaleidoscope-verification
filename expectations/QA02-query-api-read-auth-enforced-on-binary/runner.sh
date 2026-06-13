#!/usr/bin/env bash
# QA02 — read-path bearer auth is ENFORCED by the DEPLOYED query-api binary
# (read-path-query-api-auth-v0 slice 3a wires router_with_auth(Some(validator))
# from the resolved KALEIDOSCOPE_QUERY_AUTH_* config; ADR-0074 DD1/DD3/DD6).
#
# Boot the real image with a complete read-auth config (issuer
# kaleidoscope-harness, audience kaleidoscope-query, the harness HS256 secret,
# a catalogue holding `harness-tenant`) and NO env tenant, then hit
# /api/v1/query_range over HTTP with a battery of bearers.
#
# The security contract under attack (query-http-common
# resolve_request_tenant_or_refuse, 3-arm, no `else env_tenant`):
#   - VALID query-audience bearer for a catalogued tenant -> 200 success
#     (scopes to the TOKEN's tenant; empty store -> empty result, still 200).
#   - NO bearer            -> 401, NEVER 200  (no-bearer-bypass, R3 — must not
#                             fall through to any env tenant).
#   - INGEST-audience token -> 401            (audience fence, DD6: the read
#                             path accepts only `kaleidoscope-query`).
#   - wrong issuer / uncatalogued tenant / unknown role / expired /
#     forged-signature / alg=none / malformed -> 401 each.
# Every refusal must be 401 (not 200, not 500) and must not echo a secret.
#
# Transition-proof: if any adversarial bearer (above all NO-bearer or the
# ingest-audience token) is served 200, this is RED and names the breach.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

MINT="$HARNESS_DIR/mint-ingest-jwt.sh"
[[ -x "$MINT" ]] || { echo "FAIL: mint helper $MINT not executable" >&2; exit 1; }

# Auth fixtures the container will mount: the harness HS256 secret (the same
# bytes the mint helper signs with) and a catalogue holding harness-tenant.
cp "$HARNESS_DIR/jwt.secret" "$EVIDENCE_DIR/auth-secret"
cp "$HARNESS_DIR/tenants.toml" "$EVIDENCE_DIR/auth-catalogue.toml"

# A SEPARATE attacker secret for the forged-signature-under-wrong-key case.
printf 'qa02-attacker-key-not-the-real-secret' > "$EVIDENCE_DIR/attacker-secret"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# --- mint the bearer battery (host-side; HS256 over harness/jwt.secret) ---
TOK_VALID=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_INGEST=$(ISS=kaleidoscope-harness AUD=kaleidoscope-cluster TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_WRONGISS=$(ISS=evil-issuer AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_GHOST=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=ghost-tenant ROLE=viewer "$MINT")
TOK_BADROLE=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=intruder "$MINT")
TOK_EXPIRED=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer TTL_SECS=-3600 "$MINT")
TOK_WRONGKEY=$(SECRET_FILE="$EVIDENCE_DIR/attacker-secret" ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
# forged: a valid token with its signature mutated (last char rotated).
last="${TOK_VALID: -1}"; rep=$([[ "$last" == "A" ]] && echo B || echo A)
TOK_FORGED="${TOK_VALID:0:${#TOK_VALID}-1}$rep"
# alg=none: well-formed header/payload, empty signature.
EXP_FUT=$(( $(date -u +%s) + 3600 ))
NONE_H=$(printf '%s' '{"alg":"none","typ":"JWT"}' | b64url)
NONE_P=$(printf '%s' "{\"iss\":\"kaleidoscope-harness\",\"aud\":\"kaleidoscope-query\",\"exp\":${EXP_FUT},\"tenant_id\":\"harness-tenant\",\"kaleidoscope_role\":\"viewer\"}" | b64url)
TOK_ALGNONE="${NONE_H}.${NONE_P}."

export TOK_VALID TOK_INGEST TOK_WRONGISS TOK_GHOST TOK_BADROLE TOK_EXPIRED TOK_WRONGKEY TOK_FORGED TOK_ALGNONE

INLINE='
QAPI_NAME="qa02-qapi-$$"
cleanup() { docker stop --time 5 "$QAPI_NAME" >/dev/null 2>&1 || true; docker rm "$QAPI_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$QAPI_NAME" \
    -v "$DATA_HOST:/data" \
    -v "'"$EVIDENCE_DIR"'/auth-secret:/auth/jwt.secret:ro" \
    -v "'"$EVIDENCE_DIR"'/auth-catalogue.toml:/auth/tenants.toml:ro" \
    -e KALEIDOSCOPE_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_QUERY_AUTH_SECRET_FILE=/auth/jwt.secret \
    -e KALEIDOSCOPE_QUERY_AUTH_CATALOGUE=/auth/tenants.toml \
    -e RUST_LOG=info \
    -p 19097:9090 "$QAPI_IMAGE" > /dev/null

# readiness: poll the port (auth-on, no env tenant still binds via sentinel probe)
READY=""
for _ in $(seq 1 30); do
    if curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19097/api/v1/query_range?query=up" 2>/dev/null | grep -qE "^[0-9]{3}$"; then READY=yes; break; fi
    docker logs "$QAPI_NAME" 2>&1 | grep -q "listener_bound\|query_api_starting" && { READY=yes; break; }
    sleep 1
done
[[ "$READY" == "yes" ]] || { echo "query-api never became ready" >&2; docker logs "$QAPI_NAME" >&2 || true; exit 1; }
sleep 1

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(date -u +%s)
# $1=label  $2=bearer (empty = NO Authorization header)
probe() {
    local label="$1" bearer="$2" out="'"$EVIDENCE_DIR"'/body-$1.json" hdr="'"$EVIDENCE_DIR"'/hdr-$1.txt"
    local code
    if [[ -n "$bearer" ]]; then
        code=$(curl -G -sS -D "$hdr" -o "$out" -w "%{http_code}" -H "Authorization: Bearer $bearer" \
            --data-urlencode "query=up" --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode "step=15s" \
            "http://localhost:19097/api/v1/query_range")
    else
        code=$(curl -G -sS -D "$hdr" -o "$out" -w "%{http_code}" \
            --data-urlencode "query=up" --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode "step=15s" \
            "http://localhost:19097/api/v1/query_range")
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

docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" QA02 "$INLINE"

OUT="$EVIDENCE_DIR/QA02.stdout.txt"
code() { grep -oE "code_$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- positive control: a valid query-audience bearer is served ---
CV=$(code valid)
[[ "$CV" == "200" ]] || { cat "$EVIDENCE_DIR/body-valid.json" >&2; fail "valid query-audience bearer was not served 200 (got $CV) — auth wrongly rejects a good token, or the endpoint is broken"; }
jq -e '.status=="success"' "$EVIDENCE_DIR/body-valid.json" >/dev/null \
    || { cat "$EVIDENCE_DIR/body-valid.json" >&2; fail "valid bearer: body .status is not success"; }
echo "OK valid -> 200 success"

# --- the two security-critical refusals, called out explicitly ---
CN=$(code nobearer)
[[ "$CN" != "200" ]] || { cat "$EVIDENCE_DIR/body-nobearer.json" >&2; fail "NO-BEARER REQUEST WAS SERVED 200 — no-bearer-bypass (R3) BREACHED: auth-on query-api fell through to data without a bearer"; }
[[ "$CN" == "401" ]] || fail "no bearer: expected 401, got $CN"
grep -qi '^WWW-Authenticate:[[:space:]]*Bearer' "$EVIDENCE_DIR/hdr-nobearer.txt" \
    || echo "WARN: no-bearer 401 lacks WWW-Authenticate: Bearer (RFC 6750 contract); not failing on header alone"

CI=$(code ingest)
[[ "$CI" != "200" ]] || { cat "$EVIDENCE_DIR/body-ingest.json" >&2; fail "INGEST-AUDIENCE TOKEN WAS SERVED 200 — audience fence (DD6) BREACHED: a kaleidoscope-cluster/ingest token read metrics on the kaleidoscope-query path"; }
[[ "$CI" == "401" ]] || fail "ingest-audience token: expected 401, got $CI"
echo "OK no-bearer -> 401 (R3 holds); ingest-audience -> 401 (audience fence holds)"

# --- the rest of the adversarial battery: each must be 401 ---
for c in wrongiss ghost badrole expired wrongkey forged algnone malformed; do
    cc=$(code "$c")
    [[ "$cc" == "401" ]] || { cat "$EVIDENCE_DIR/body-$c.json" >&2; fail "$c bearer: expected 401, got $cc (a bad token was not fail-closed)"; }
done
echo "OK adversarial battery (wrongiss/ghost/badrole/expired/wrongkey/forged/algnone/malformed) -> 401 each"

# --- redaction: no 401 body may echo a raw HS256 secret byte ---
if grep -rqi 'qa02-attacker-key\|BEGIN.*KEY' "$EVIDENCE_DIR"/body-*.json 2>/dev/null; then
    fail "a refusal body leaked secret-shaped material"
fi

echo "QA02 satisfied — deployed query-api enforces read-auth: valid query-audience bearer served, every adversarial bearer (incl no-bearer R3 and ingest-audience fence) refused 401, no env-tenant fall-through, no secret leak"
