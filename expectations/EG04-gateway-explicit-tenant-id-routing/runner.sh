#!/usr/bin/env bash
# EG04 — a record carrying an explicit OTLP resource tenant.id is routed
# to THAT tenant, overriding the gateway's configured default tenant.
# Covers UC-GWTEN-001. The gateway runs with KALEIDOSCOPE_DEFAULT_TENANT=
# acme; a metric tagged tenant.id=globex lands under globex (visible to a
# globex query-api, invisible to an acme query-api) — explicit routing,
# not the default fallback. Round-trip gateway -> Pulse -> query-api.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="eg04-gw-$$"
cleanup() { docker stop --time 5 "$GW_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14381:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
# Explicit per-record tenant.id=globex, while the gateway default is acme.
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14381 --otlp-insecure --otlp-http \
    --duration 1s --rate 2 --otlp-attributes tenant.id=\"globex\" >/dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

qcount() { # $1=tenant -> writes count to stdout
    local N="eg04-q-$1-$$"
    docker run --rm -d --name "$N" -v "$SHARED_DATA:/data" \
        -e KALEIDOSCOPE_QUERY_TENANT="$1" -e RUST_LOG=info -p 19181:9090 "$QAPI_IMAGE" > /dev/null
    sleep 3
    local S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); local E=$(( $(date -u +%s) + 120 ))
    curl -sS -G -o "'"$EVIDENCE_DIR"'/$1.json" "http://localhost:19181/api/v1/query_range" \
        --data-urlencode query=gen --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode step=15s >/dev/null
    docker stop --time 3 "$N" >/dev/null 2>&1 || true; docker rm "$N" >/dev/null 2>&1 || true
}
qcount globex
qcount acme
echo "globex_count=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/globex.json")"
echo "acme_count=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/acme.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG04 "$INLINE"

OUT="$EVIDENCE_DIR/EG04.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
[[ "$(val globex_count)" -ge 1 ]] || { echo "explicit tenant.id=globex did NOT route to globex (count $(val globex_count))" >&2; exit 1; }
[[ "$(val acme_count)" == "0" ]] || { echo "record leaked into the default tenant acme (count $(val acme_count)); explicit tenant.id not honoured" >&2; exit 1; }
echo "OK — an explicit resource tenant.id=globex routes the record to globex ($(val globex_count) series), overriding the default tenant acme ($(val acme_count) series)"
