#!/usr/bin/env bash
# LQ09 — over a known mixed-severity/body fixture, log-query-api treats
# `min_severity` case-insensitively (UC-LOG-003: `warn` behaves as `WARN`)
# and composes `min_severity` with `body_contains` so BOTH filters apply
# (UC-LOG-018). Records round-trip gateway -> Lumen -> log-query-api.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="lq09-gw-$$"; LQ_NAME="lq09-lqapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14331:4318 "$GW_IMAGE" > /dev/null
SAW=""; for i in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2

TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
emit() { # severity-number severity-text body
  docker run --rm --network host "$TG" logs --otlp-endpoint localhost:14331 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 --severity-number "$1" --severity-text "$2" --body "$3" \
    --otlp-attributes service.name=\"lq09-pilot\" >/dev/null 2>&1 || { echo "emit $3 failed" >&2; exit 1; }
}
emit 9  Info  lq09-db-info       # INFO, body has db -> excluded by min_severity=ERROR
emit 13 Warn  lq09-warn-line     # WARN
emit 17 Error lq09-db-error      # ERROR, body has db -> the only compose match
emit 17 Error lq09-other-error   # ERROR, body lacks db -> excluded by body_contains=db

docker stop --time 10 "$GW_NAME" > /dev/null; docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$LQ_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -e RUST_LOG=info -p 19122:9091 "$LQAPI_IMAGE" > /dev/null
sleep 3
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
URL="http://localhost:19122/api/v1/logs"
q() { curl -sS -G "$URL" --data-urlencode "start=${START}" --data-urlencode "end=${END}" "$@"; }

q --data-urlencode min_severity=warn  > "'"$EVIDENCE_DIR"'/sev-lower.json"
q --data-urlencode min_severity=WARN  > "'"$EVIDENCE_DIR"'/sev-upper.json"
q --data-urlencode body_contains=db   > "'"$EVIDENCE_DIR"'/body-db.json"
q --data-urlencode min_severity=ERROR --data-urlencode body_contains=db > "'"$EVIDENCE_DIR"'/compose.json"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" LQ09 "$INLINE"

cnt()  { jq 'length' "$1"; }
bodies() { jq -r '.[].body' "$1" | sort -u | tr '\n' ',' ; }

# UC-LOG-003: lowercase warn behaves exactly as uppercase WARN.
LO=$(cnt "$EVIDENCE_DIR/sev-lower.json"); UP=$(cnt "$EVIDENCE_DIR/sev-upper.json")
[[ "$LO" -gt 0 && "$LO" == "$UP" ]] || { echo "FAIL: min_severity=warn ($LO) != WARN ($UP) or empty" >&2; exit 1; }

# UC-LOG-018: ERROR + body_contains=db narrows to ONLY the db-error record.
DB_ONLY=$(bodies "$EVIDENCE_DIR/body-db.json")          # expect db-info + db-error
COMPOSE=$(bodies "$EVIDENCE_DIR/compose.json")           # expect db-error only
case "$DB_ONLY" in *lq09-db-info*) : ;; *) echo "FAIL: body_contains=db missing the INFO/db record ($DB_ONLY)" >&2; exit 1;; esac
[[ "$COMPOSE" == "lq09-db-error," ]] || { echo "FAIL: compose (ERROR&db) expected only lq09-db-error, got: $COMPOSE" >&2; exit 1; }
echo "OK — min_severity is case-insensitive (warn==WARN, ${LO} records); ERROR+body_contains=db composes to only the db-error record (body-only kept the INFO/db too)"
