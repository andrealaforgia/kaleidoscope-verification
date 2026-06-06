#!/usr/bin/env bash
# EG07 — the full loop survives a graceful restart: after populating all
# three pillars, the gateway is stopped and RESTARTED on the same volume
# (it re-opens the already-populated pillars and comes up healthy), and
# all three signals remain queryable. Covers UC-LOOP-006 (loop survives a
# full restart). Distinct from D01-D03 (ungraceful kill-9 recovery per
# pillar): this is a clean restart of the writer over a populated volume,
# at the loop level.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
LOGMARK="eg07-restart"; SVC="eg07-svc"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
cleanup() { docker stop --time 5 eg07-gw1 eg07-gw2 eg07-q eg07-lq eg07-tq >/dev/null 2>&1 || true; docker rm eg07-gw1 eg07-gw2 eg07-q eg07-lq eg07-tq >/dev/null 2>&1 || true; }
trap cleanup EXIT
TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"

boot_gw() { # $1=name
    docker run --rm -d --name "$1" -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14420:4318 "$GW_IMAGE" >/dev/null
    for i in $(seq 1 30); do docker logs "$1" 2>&1 | grep -q listener_bound && return 0; sleep 0.5; done
    echo "gateway $1 never bound" >&2; return 1
}

# 1. Populate all three pillars.
boot_gw eg07-gw1 || exit 1
docker run --rm --network host "$TG" metrics --otlp-endpoint localhost:14420 --otlp-insecure --otlp-http --duration 1s --rate 2 >/dev/null 2>&1
docker run --rm --network host "$TG" logs    --otlp-endpoint localhost:14420 --otlp-insecure --otlp-http --duration 1s --rate 3 --body "$LOGMARK" >/dev/null 2>&1
docker run --rm --network host "$TG" traces  --otlp-endpoint localhost:14420 --otlp-insecure --otlp-http --traces 3 --child-spans 1 --service "$SVC" >/dev/null 2>&1
docker stop --time 10 eg07-gw1 >/dev/null; docker rm eg07-gw1 >/dev/null 2>&1 || true

# 2. RESTART the gateway on the SAME volume: it must re-open the
#    populated pillars and come up healthy (no corruption/refusal).
boot_gw eg07-gw2 || { echo "gateway did NOT re-open the populated pillars on restart" >&2; exit 1; }
docker logs eg07-gw2 > "'"$EVIDENCE_DIR"'/gateway-restart.stderr.txt" 2>&1 || true
RESTART_READY=no
grep -q "\"event\":\"ready\"\|readiness_changed.*true" "'"$EVIDENCE_DIR"'/gateway-restart.stderr.txt" && RESTART_READY=yes
echo "restart_ready=$RESTART_READY"
docker stop --time 5 eg07-gw2 >/dev/null 2>&1 || true; docker rm eg07-gw2 >/dev/null 2>&1 || true

# 3. All three signals still queryable from fresh readers.
S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
docker run --rm -d --name eg07-q -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_QUERY_TENANT=acme -p 19420:9090 "$QAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/metric.json" "http://localhost:19420/api/v1/query_range" --data-urlencode query=gen --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode step=15s >/dev/null
docker stop --time 3 eg07-q >/dev/null 2>&1 || true; docker rm eg07-q >/dev/null 2>&1 || true
docker run --rm -d --name eg07-lq -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -p 19421:9091 "$LQAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/log.json" "http://localhost:19421/api/v1/logs" --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode "body_contains=$LOGMARK" >/dev/null
docker stop --time 3 eg07-lq >/dev/null 2>&1 || true; docker rm eg07-lq >/dev/null 2>&1 || true
docker run --rm -d --name eg07-tq -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme -p 19422:9092 "$TQAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/trace.json" "http://localhost:19422/api/v1/traces" --data-urlencode "service=$SVC" --data-urlencode "start=$S" --data-urlencode "end=$E" >/dev/null
docker stop --time 3 eg07-tq >/dev/null 2>&1 || true; docker rm eg07-tq >/dev/null 2>&1 || true

echo "metric_series=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/metric.json")"
echo "log_count=$(jq length "'"$EVIDENCE_DIR"'/log.json")"
echo "trace_spans=$(jq length "'"$EVIDENCE_DIR"'/trace.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG07 "$INLINE"

OUT="$EVIDENCE_DIR/EG07.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
grep -qx 'restart_ready=yes' "$OUT" || { echo "gateway did not come up healthy after restart over the populated volume" >&2; exit 1; }
[[ "$(val metric_series)" -ge 1 ]] || { echo "metric did not survive the full restart" >&2; exit 1; }
[[ "$(val log_count)"     -ge 1 ]] || { echo "log did not survive the full restart" >&2; exit 1; }
[[ "$(val trace_spans)"   -ge 1 ]] || { echo "trace did not survive the full restart" >&2; exit 1; }
echo "OK — after populating all three pillars and a graceful gateway restart over the same volume (re-opened healthy), all three signals remain queryable (metric=$(val metric_series), log=$(val log_count), trace=$(val trace_spans))"
