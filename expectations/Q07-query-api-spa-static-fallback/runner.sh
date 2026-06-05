#!/usr/bin/env bash
# Q07 — query-api serves Prism's static bundle from the same origin when
# KALEIDOSCOPE_QUERY_STATIC_DIR is set: existing files are served
# directly, unknown non-API paths fall back to index.html with a 200 (the
# SPA deep-link contract, DD6 — NOT a 404), and the /api/v1 route still
# WINS over the static fallback. With the env unset, an unknown path is a
# 404 (API-only). Integrator-facing.
#
# Given a static dir with index.html + config.json and query-api started
#       with KALEIDOSCOPE_QUERY_STATIC_DIR pointing at it
# When various paths are requested
# Then: an existing file (/config.json) is served (200, its bytes); an
#       unknown deep link (/dashboards/42) falls back to index.html (200,
#       NOT 404); /api/v1/query_range is the API (JSON status, not html).
#       And with NO static dir, the deep link is a 404.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"

INLINE='
cp -r "'"$EXP_DIR"'/static" "$DATA_HOST/static"
NAME="q07-$$"; NAME2="q07b-$$"
cleanup() { docker rm -f "$NAME" "$NAME2" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# --- query-api WITH a static dir ---
docker run --rm -d --name "$NAME" \
    -v "$DATA_HOST:/data" -v "$DATA_HOST/static:/static:ro" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme \
    -e KALEIDOSCOPE_QUERY_STATIC_DIR=/static \
    -e RUST_LOG=info -p 19100:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
B="http://localhost:19100"
get() { curl -sS -o "$2" -w "%{http_code}" "$1"; }
echo "code_file=$(get "$B/config.json" "'"$EVIDENCE_DIR"'/config.out")"
echo "code_deeplink=$(get "$B/dashboards/42" "'"$EVIDENCE_DIR"'/deeplink.out")"
START=1700000000; END=1700000100
echo "code_api=$(get "$B/api/v1/query_range?query=gen&start=$START&end=$END&step=15s" "'"$EVIDENCE_DIR"'/api.out")"
docker rm -f "$NAME" >/dev/null 2>&1 || true

# --- query-api WITHOUT a static dir (negative control) ---
docker run --rm -d --name "$NAME2" \
    -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme \
    -e RUST_LOG=info -p 19101:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
echo "code_deeplink_nostatic=$(get "http://localhost:19101/dashboards/42" "'"$EVIDENCE_DIR"'/deeplink-nostatic.out")"
docker rm -f "$NAME2" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" Q07 "$INLINE"

OUT="$EVIDENCE_DIR/Q07.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }

# 1. Existing file served directly.
[[ "$(code code_file)" == "200" ]] || { echo "FAIL: /config.json not 200 (got $(code code_file))" >&2; cat "$EVIDENCE_DIR/config.out" >&2; exit 1; }
grep -q 'Q07-CONFIG-SENTINEL' "$EVIDENCE_DIR/config.out" || { echo "FAIL: /config.json did not serve the static file bytes" >&2; cat "$EVIDENCE_DIR/config.out" >&2; exit 1; }

# 2. Unknown deep link falls back to index.html with 200 (NOT 404).
[[ "$(code code_deeplink)" == "200" ]] || { echo "FAIL: deep link /dashboards/42 not 200 (got $(code code_deeplink)); SPA fallback missing" >&2; cat "$EVIDENCE_DIR/deeplink.out" >&2; exit 1; }
grep -q 'Q07-SPA-INDEX-SENTINEL' "$EVIDENCE_DIR/deeplink.out" || { echo "FAIL: deep link did not fall back to index.html" >&2; cat "$EVIDENCE_DIR/deeplink.out" >&2; exit 1; }

# 3. The API route WINS over the static fallback.
ASTATUS=$(jq -r '.status // empty' "$EVIDENCE_DIR/api.out" 2>/dev/null)
[[ -n "$ASTATUS" ]] || { echo "FAIL: /api/v1/query_range did not return the API JSON (status field absent); static fallback wrongly shadowed the API" >&2; head -c 300 "$EVIDENCE_DIR/api.out" >&2; exit 1; }
grep -q 'Q07-SPA-INDEX-SENTINEL' "$EVIDENCE_DIR/api.out" && { echo "FAIL: /api/v1/query_range returned index.html (static shadowed the API)" >&2; exit 1; }

# 4. Negative control: no static dir -> deep link is 404.
[[ "$(code code_deeplink_nostatic)" == "404" ]] || { echo "FAIL: with no static dir, deep link expected 404, got $(code code_deeplink_nostatic)" >&2; cat "$EVIDENCE_DIR/deeplink-nostatic.out" >&2; exit 1; }

echo "OK — query-api SPA static fallback: /config.json served directly (200, file bytes); unknown deep link /dashboards/42 falls back to index.html (200, not 404); /api/v1/query_range stays the API (status=${ASTATUS}, not html); and with no static dir the same deep link is a 404. Same-origin SPA serving with the API route winning."
