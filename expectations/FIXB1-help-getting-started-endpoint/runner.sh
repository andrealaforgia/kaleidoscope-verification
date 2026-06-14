#!/usr/bin/env bash
# FIXB1 — a plain-text getting-started endpoint GET /help on :9090, an EXACT
# route that wins over the Prism SPA fallback (GET / stays the SPA). Sprint item
# FIX-B.1, PO-confirmed route + content.
#
# GET :9090/help -> 200, plain text, listing the four example curls
# (/api/v1/query_range, /api/v1/logs, /api/v1/traces service-window,
# /api/v1/traces/by_id) and the accepted time format. The route is an exact
# router route, so it must answer regardless of whether the Prism static dir is
# set (this runtime has no static dir -> a 200 here also proves /help is NOT
# gated behind the SPA fallback).
#
# Transition-proof: RED now (no /help route -> 404), GREEN when the plain-text
# /help endpoint lands.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
RT="fixb1-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run -d --name "$RT" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19180:9090 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19180/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
echo "help_code=$(curl -s -o "'"$EVIDENCE_DIR"'/help.txt" -w "%{http_code}" "http://localhost:19180/help")"
echo "help_ctype=$(curl -s -o /dev/null -w "%{content_type}" "http://localhost:19180/help")"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" FIXB1 "$INLINE"

OUT="$EVIDENCE_DIR/FIXB1.stdout.txt"
HC=$(grep -oE 'help_code=[0-9]+' "$OUT" | tail -1 | cut -d= -f2)
BODY="$EVIDENCE_DIR/help.txt"
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

[ "$HC" = "200" ] || fail "GET /help not 200 (got $HC) — no plain-text getting-started endpoint"
for needle in '/api/v1/query_range' '/api/v1/logs' '/api/v1/traces' '/api/v1/traces/by_id'; do
    grep -qF "$needle" "$BODY" || fail "GET /help body does not mention $needle (the 4 example curls must be listed)"
done
grep -qiE 'rfc.?3339|unix|seconds|[0-9]{4}-[0-9]{2}-[0-9]{2}t' "$BODY" || fail "GET /help body does not state the accepted time format"
echo "FIXB1 satisfied — GET /help returns a plain-text getting-started with the four example endpoints and the time format."
