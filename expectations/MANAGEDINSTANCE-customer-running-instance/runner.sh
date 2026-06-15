#!/usr/bin/env bash
# MANAGEDINSTANCE — the delivery-owned, always-current running instance the
# Customer is handed. She operates nothing (no build/up/seed/reset); she only
# (a) sends OTLP from her own app, and (b) queries the documented interface
# (query endpoints + the on-screen dashboard). This probes the LIVE managed
# instance at its FIXED address — it does NOT build anything (verification stays
# independent of the delivery that owns the instance; re-run after each redeploy).
#
# Fixed address under test:
#   OTLP ingest : http://localhost:4318 (HTTP) / localhost:4317 (gRPC)
#   query/dash  : http://localhost:9090 (dashboard + metrics), :9091 logs, :9092 traces
#
# Asserts:
#   1. dashboard answers (:9090/ -> 200 HTML);
#   2. demo/sample telemetry is present WITHOUT her building anything — a
#      kaleidoscope-demo trace is queryable and the request_count metric returns
#      a series (delivery seeded it via a pre-built path);
#   3. her two actions work end to end: an OTLP export to the ingest address
#      round-trips through the query interface CORRELATED — the trace's logs are
#      retrievable by its id with NO time window (which also confirms the
#      instance is on the current build, since no-window logs-by-trace_id is the
#      current-build behaviour).
set -euo pipefail
EVIDENCE_DIR="$1"
APP="$(dirname "$0")/../PG1-otlp-external-sdk-trace/pg1_app.py"
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. dashboard
read -r DCODE DCTYPE < <(curl -s -o /dev/null -w '%{http_code} %{content_type}' "http://localhost:9090/" 2>/dev/null; echo)
[ "$DCODE" = "200" ] || fail "dashboard http://localhost:9090/ did not answer 200 (got $DCODE) — the query/dashboard interface is not reachable"
case "$DCTYPE" in text/html*) : ;; *) fail "dashboard / did not serve HTML (content-type $DCTYPE)";; esac

NOW=$(date +%s); S=$((NOW-80000)); E=$((NOW))

# 2. demo data present without a source build — discover the demo trace from the
#    observable window (never hardcode the generator's fixed id).
curl -s -o "$EVIDENCE_DIR/demo_window.json" "http://localhost:9092/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
DEMO_TID=$(python3 -c 'import json;d=json.load(open("'"$EVIDENCE_DIR"'/demo_window.json"));ids=[x.get("trace_id") for x in (d if isinstance(d,list) else []) if x.get("trace_id")];print(ids[0] if ids else "")' 2>/dev/null || echo "")
[ -n "$DEMO_TID" ] || fail "no kaleidoscope-demo trace is queryable on the instance — sample telemetry is not present (she would have to seed it herself)"
MSERIES=$(curl -s "http://localhost:9090/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo 0)
[ "${MSERIES:-0}" -ge 1 ] 2>/dev/null || fail "the demo request_count metric returns no series — sample telemetry not present"

# 3. her two actions: OTLP ingest -> query interface, correlated, no-window by id
docker run --rm --network host -v "$APP:/pg1_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://localhost:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /pg1_app.py" \
    > "$EVIDENCE_DIR/app.out" 2> "$EVIDENCE_DIR/app.err" \
    || fail "OTLP ingest to http://localhost:4318 was not accepted — her 'send telemetry' action does not work ($(tail -1 "$EVIDENCE_DIR/app.err" 2>/dev/null))"
TID=$(grep -oE "PG1_REPORT=.*" "$EVIDENCE_DIR/app.out" | sed "s/PG1_REPORT=//" | python3 -c "import sys,json;print(json.load(sys.stdin)['trace_id'])" 2>/dev/null || echo "")
[ -n "$TID" ] || fail "the OTLP app did not report a trace id"
sleep 2
curl -s -o "$EVIDENCE_DIR/byid_trace.json" "http://localhost:9092/api/v1/traces/by_id?trace_id=${TID}"
SPANS=$(python3 -c 'import json;d=json.load(open("'"$EVIDENCE_DIR"'/byid_trace.json"));print(len(d) if isinstance(d,list) else 0)' 2>/dev/null || echo 0)
[ "${SPANS:-0}" -ge 1 ] 2>/dev/null || fail "her exported trace did not come back through the traces query interface ($SPANS spans)"
# logs by trace id with NO window (current-build behaviour + correlation)
LCODE=$(curl -s -o "$EVIDENCE_DIR/byid_logs.json" -w '%{http_code}' "http://localhost:9091/api/v1/logs?trace_id=${TID}")
[ "$LCODE" = "200" ] || fail "logs-by-trace_id WITHOUT a window returned $LCODE (expected 200) — the instance is not on the current build"
LAPP=$(python3 -c 'import json;d=json.load(open("'"$EVIDENCE_DIR"'/byid_logs.json"));d=d if isinstance(d,list) else [];print(sum(1 for l in d if "checkout failed for customer" in str(l.get("body",""))))' 2>/dev/null || echo 0)
[ "${LAPP:-0}" -ge 1 ] 2>/dev/null || fail "her trace's in-span log was not retrievable by trace id with no window — correlation does not work on the instance"

echo "MANAGEDINSTANCE satisfied — fixed address reachable for both customer actions (OTLP ingest :4318 + query/dashboard :9090/:9091/:9092); sample telemetry present without a source build (kaleidoscope-demo trace ${DEMO_TID:0:8}…, request_count ${MSERIES} series); an OTLP export round-trips correlated (her trace ${TID:0:8}… -> ${SPANS} spans, its in-span log retrievable by id with NO window) — on the current build."
