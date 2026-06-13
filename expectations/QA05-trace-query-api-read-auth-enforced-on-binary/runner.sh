#!/usr/bin/env bash
# QA05 — read-path bearer auth is ENFORCED by the DEPLOYED trace-query-api
# binary on BOTH its routes (read-path-query-api-auth-v0 slice 3c `6fb7f9a`:
# trace-query-api main.rs resolves KALEIDOSCOPE_TRACE_QUERY_AUTH_* and calls
# router_with_auth(store, tenant, auth); ADR-0074). The traces analogue of
# QA02/QA03.
#
# The trace API has TWO routes (lib.rs: "auth shared by BOTH the window route
# and the lookup-by-id route"), so a wiring defect could guard one and miss the
# other. This attacks both:
#   - window  GET /api/v1/traces?service=&start=&end=
#   - by-id   GET /api/v1/traces/by_id?trace_id=<32-hex>
#
# Booted with a complete read-auth config (audience kaleidoscope-query,
# catalogue=harness-tenant) and NO env tenant:
#   - a valid kaleidoscope-query bearer -> NOT 401 on both routes (window 200);
#   - NO bearer            -> 401 on BOTH routes (no-bearer-bypass R3);
#   - ingest-audience      -> 401 on BOTH routes (audience fence DD6);
#   - expired / malformed  -> 401 on both.
#
# Transition-proof: RED (naming the breach + the route) if any adversarial
# bearer is served non-401 on EITHER route — in particular if the by_id route
# turns out to be unguarded.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

MINT="$HARNESS_DIR/mint-ingest-jwt.sh"
[[ -x "$MINT" ]] || { echo "FAIL: mint helper $MINT not executable" >&2; exit 1; }

cp "$HARNESS_DIR/jwt.secret" "$EVIDENCE_DIR/auth-secret"
cp "$HARNESS_DIR/tenants.toml" "$EVIDENCE_DIR/auth-catalogue.toml"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
TOK_VALID=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_INGEST=$(ISS=kaleidoscope-harness AUD=kaleidoscope-cluster TENANT=harness-tenant ROLE=viewer "$MINT")
TOK_EXPIRED=$(ISS=kaleidoscope-harness AUD=kaleidoscope-query TENANT=harness-tenant ROLE=viewer TTL_SECS=-3600 "$MINT")
export TOK_VALID TOK_INGEST TOK_EXPIRED

INLINE='
TQAPI_NAME="qa05-tqapi-$$"
cleanup() { docker stop --time 5 "$TQAPI_NAME" >/dev/null 2>&1 || true; docker rm "$TQAPI_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$TQAPI_NAME" \
    -v "$DATA_HOST:/data" \
    -v "'"$EVIDENCE_DIR"'/auth-secret:/auth/jwt.secret:ro" \
    -v "'"$EVIDENCE_DIR"'/auth-catalogue.toml:/auth/tenants.toml:ro" \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_SECRET_FILE=/auth/jwt.secret \
    -e KALEIDOSCOPE_TRACE_QUERY_AUTH_CATALOGUE=/auth/tenants.toml \
    -e RUST_LOG=info -p 19093:9092 "$TQAPI_IMAGE" > /dev/null

READY=""; for _ in $(seq 1 30); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19093/api/v1/traces" 2>/dev/null | grep -qE "^[0-9]{3}$" && { READY=yes; break; }
    docker logs "$TQAPI_NAME" 2>&1 | grep -q "listener_bound\|trace_query_api_starting" && { READY=yes; break; }
    sleep 1; done
[[ "$READY" == "yes" ]] || { echo "trace-query-api never ready" >&2; docker logs "$TQAPI_NAME" >&2 || true; exit 1; }
sleep 1

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
TID="0123456789abcdef0123456789abcdef"
WIN="http://localhost:19093/api/v1/traces?service=svc&start=${START}&end=${END}"
BYID="http://localhost:19093/api/v1/traces/by_id?trace_id=${TID}"
probe() { # $1 label  $2 url  $3 bearer(empty=none)
    local out="'"$EVIDENCE_DIR"'/body-$1.json" code
    if [[ -n "$3" ]]; then code=$(curl -sS -o "$out" -w "%{http_code}" -H "Authorization: Bearer $3" "$2");
    else code=$(curl -sS -o "$out" -w "%{http_code}" "$2"); fi
    echo "code_$1=$code"
}
probe win_valid     "$WIN"  "$TOK_VALID"
probe win_nobearer  "$WIN"  ""
probe win_ingest    "$WIN"  "$TOK_INGEST"
probe win_expired   "$WIN"  "$TOK_EXPIRED"
probe win_malformed "$WIN"  "notajwt"
probe byid_valid    "$BYID" "$TOK_VALID"
probe byid_nobearer "$BYID" ""
probe byid_ingest   "$BYID" "$TOK_INGEST"

docker logs "$TQAPI_NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-trace-query-api.sh" "$EVIDENCE_DIR" QA05 "$INLINE"

OUT="$EVIDENCE_DIR/QA05.stdout.txt"
code() { grep -oE "code_$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

# window route
[[ "$(code win_valid)" == "200" ]] || fail "window: valid bearer not 200 (got $(code win_valid))"
[[ "$(code win_nobearer)" == "401" ]] || fail "WINDOW ROUTE no-bearer not 401 (got $(code win_nobearer)) — no-bearer-bypass R3 breached on /api/v1/traces"
[[ "$(code win_ingest)" == "401" ]] || fail "window: ingest-audience not 401 (got $(code win_ingest)) — audience fence breached"
[[ "$(code win_expired)" == "401" ]] || fail "window: expired not 401 (got $(code win_expired))"
[[ "$(code win_malformed)" == "401" ]] || fail "window: malformed not 401 (got $(code win_malformed))"
echo "OK window /api/v1/traces: valid 200; no-bearer/ingest/expired/malformed 401"

# by-id route — the sibling route must be guarded too
[[ "$(code byid_valid)" != "401" ]] || fail "by_id: a VALID bearer was 401 (got $(code byid_valid)) — auth wrongly rejects on the by_id route"
[[ "$(code byid_nobearer)" == "401" ]] || fail "BY_ID ROUTE no-bearer not 401 (got $(code byid_nobearer)) — the lookup-by-id route /api/v1/traces/by_id is UNGUARDED (auth missed a route)"
[[ "$(code byid_ingest)" == "401" ]] || fail "by_id: ingest-audience not 401 (got $(code byid_ingest)) — audience fence missing on the by_id route"
echo "OK by_id /api/v1/traces/by_id: valid non-401 ($(code byid_valid)); no-bearer/ingest 401 (route IS guarded)"

echo "QA05 satisfied — deployed trace-query-api enforces read-auth on BOTH the window and by_id routes (no-bearer R3 + audience fence hold on each), no unguarded route"
