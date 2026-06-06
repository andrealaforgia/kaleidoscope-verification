#!/usr/bin/env bash
# EG06 — a log carrying a trace_id and the matching trace can be
# correlated by id across pillars (the trace<->log join that makes
# unified observability useful). Covers UC-LOOP-005.
#
# telemetrygen can't pin a shared trace id, so: ingest a trace, DISCOVER
# its trace_id from trace-query-api, ingest a LOG stamped with that same
# trace_id, then show the log (via log-query-api) carries it AND the trace
# (via trace-query-api /by_id) resolves to spans for it.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SVC="eg06-svc"; LOGMARK="eg06-corr"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
cleanup() { docker stop --time 5 eg06-gw eg06-tq eg06-lq >/dev/null 2>&1 || true; docker rm eg06-gw eg06-tq eg06-lq >/dev/null 2>&1 || true; }
trap cleanup EXIT
TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"

boot_gw() { docker run --rm -d --name eg06-gw -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14410:4318 "$GW_IMAGE" >/dev/null
  for i in $(seq 1 30); do docker logs eg06-gw 2>&1 | grep -q listener_bound && return 0; sleep 0.5; done; echo "gw never bound" >&2; return 1; }

# 1. Ingest a trace.
boot_gw || exit 1
docker run --rm --network host "$TG" traces --otlp-endpoint localhost:14410 --otlp-insecure --otlp-http --traces 1 --child-spans 1 --service "$SVC" >/dev/null 2>&1
docker stop --time 10 eg06-gw >/dev/null; docker rm eg06-gw >/dev/null 2>&1 || true

# 2. Discover the trace_id from trace-query-api.
docker run --rm -d --name eg06-tq -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme -p 19410:9092 "$TQAPI_IMAGE" >/dev/null; sleep 3
S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
curl -sS -G -o /tmp/win.json "http://localhost:19410/api/v1/traces" --data-urlencode "service=$SVC" --data-urlencode "start=$S" --data-urlencode "end=$E" >/dev/null
TID=$(jq -r ".[0].trace_id // empty" /tmp/win.json)
echo "trace_id=$TID"
[[ -n "$TID" ]] || { echo "no trace_id discovered" >&2; exit 1; }

# 3. Ingest a log STAMPED with that same trace_id.
boot_gw || exit 1
docker run --rm --network host "$TG" logs --otlp-endpoint localhost:14410 --otlp-insecure --otlp-http \
    --duration 1s --rate 2 --body "$LOGMARK" --trace-id "$TID" >/dev/null 2>&1
docker stop --time 10 eg06-gw >/dev/null; docker rm eg06-gw >/dev/null 2>&1 || true

# 4. The log carries that trace_id (bytes -> hex).
docker run --rm -d --name eg06-lq -v "$SHARED_DATA:/data" -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -p 19411:9091 "$LQAPI_IMAGE" >/dev/null; sleep 3
curl -sS -G -o "'"$EVIDENCE_DIR"'/log.json" "http://localhost:19411/api/v1/logs" --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode "body_contains=$LOGMARK" >/dev/null
LOG_TID=$(jq -r ".[0].trace_id[]?" "'"$EVIDENCE_DIR"'/log.json" | awk "{printf \"%02x\",\$1}")
echo "log_trace_id=$LOG_TID"
docker stop --time 3 eg06-lq >/dev/null 2>&1 || true; docker rm eg06-lq >/dev/null 2>&1 || true

# 5. The trace resolves by that id.
BYID=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/byid.json" -w "%{http_code}" "http://localhost:19410/api/v1/traces/by_id" --data-urlencode "trace_id=$TID")
echo "byid_code=$BYID"
echo "byid_spans=$(jq length "'"$EVIDENCE_DIR"'/byid.json")"
docker stop --time 3 eg06-tq >/dev/null 2>&1 || true; docker rm eg06-tq >/dev/null 2>&1 || true
cp /tmp/win.json "'"$EVIDENCE_DIR"'/window.json"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" EG06 "$INLINE"

OUT="$EVIDENCE_DIR/EG06.stdout.txt"
TID=$(grep -oE 'trace_id=[0-9a-f]+' "$OUT" | head -1 | cut -d= -f2)
LOG_TID=$(grep -oE 'log_trace_id=[0-9a-f]+' "$OUT" | tail -1 | cut -d= -f2)
BYID_SPANS=$(grep -oE 'byid_spans=[0-9]+' "$OUT" | tail -1 | cut -d= -f2)
[[ -n "$TID" && "$TID" =~ ^[0-9a-f]{32}$ ]] || { echo "no valid trace_id discovered" >&2; exit 1; }
[[ "$LOG_TID" == "$TID" ]] || { echo "log's trace_id ($LOG_TID) does not match the trace's id ($TID); not correlatable" >&2; exit 1; }
[[ "$BYID_SPANS" -ge 1 ]] || { echo "trace did not resolve by the shared id" >&2; exit 1; }
echo "OK — a log carries trace_id $TID and the trace resolves by that same id ($BYID_SPANS spans); the log<->trace join holds across pillars"
