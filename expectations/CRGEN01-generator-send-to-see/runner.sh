#!/usr/bin/env bash
# CRGEN-01 — send-to-see via the FIRST-PARTY generator. The
# kaleidoscope-telemetrygen bin, pointed at a live consolidated runtime, makes
# all three signals queryable: the metric request_count (:9090), the app log
# "checkout failed: card declined" (:9091), and the trace span
# "GET /api/v1/query_range" / service kaleidoscope-demo under the fixed trace id
# 4bf92f3577b34da6a3ce929d0e0e4736 (:9092 by-id), tenant acme.
#
# This is our-generator -> our-gateway (self-compat), deliberately distinct from
# PG1 (external SDK, cross-compat). consolidated-runtime-v0 + generator slice 2.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"

cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
echo "building runtime + generator images from the committed snapshot ..." >&2
docker build -q -t kx-runtime:crgen -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:crgen -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="crgen-net-$$"; RT="crgen-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null

docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn \
    -p 19190:9090 -p 19191:9091 -p 19192:9092 kx-runtime:crgen > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19190/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

# the first-party generator emits all three signals to the runtime (OTLP/gRPC).
docker run --rm --network "$NET" \
    -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RT:4317" -e KALEIDOSCOPE_TENANT=acme \
    kx-gen:crgen > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" \
    || { echo "generator exited non-zero against a LIVE runtime" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }

sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
echo "m_series=$(curl -s "http://localhost:19190/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" | tee "$EVIDENCE_DIR/metrics.json" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo NA)"
echo "log_hits=$(curl -s "http://localhost:19191/api/v1/logs?start=${S}&end=${E}&body_contains=declined" | tee "$EVIDENCE_DIR/logs.json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sum(1 for r in (d if isinstance(d,list) else []) if "declined" in str(r.get("body",""))))' 2>/dev/null || echo NA)"
# DISCOVER the trace id from the observable window (service=kaleidoscope-demo),
# never a constant the implementer pins for us — assert the id the generator
# actually emitted round-trips through by-id.
curl -s -o "$EVIDENCE_DIR/window.json" "http://localhost:19192/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
TID=$(python3 -c 'import json;s=json.load(open("'"$EVIDENCE_DIR"'/window.json"));ids=[x.get("trace_id") for x in (s if isinstance(s,list) else []) if x.get("trace_id")];print(ids[0] if ids else "")' 2>/dev/null || echo "")
echo "discovered_trace_id=${TID}"
curl -s -o "$EVIDENCE_DIR/byid.json" -w 'byid_code=%{http_code}\n' "http://localhost:19192/api/v1/traces/by_id?trace_id=${TID}"
echo "span_count=$(python3 -c 'import json;s=json.load(open("'"$EVIDENCE_DIR"'/byid.json"));print(len(s) if isinstance(s,list) else 0)' 2>/dev/null || echo NA)"
docker logs "$RT" > "$EVIDENCE_DIR/runtime.stderr.txt" 2>&1 || true

fail() { echo "FAIL: $1" >&2; exit 1; }

MS=$(python3 -c 'import json;print(len(json.load(open("'"$EVIDENCE_DIR"'/metrics.json"))["data"]["result"]))')
LH=$(python3 -c 'import json;d=json.load(open("'"$EVIDENCE_DIR"'/logs.json"));print(sum(1 for r in (d if isinstance(d,list) else []) if "declined" in str(r.get("body",""))))')
SC=$(python3 -c 'import json;s=json.load(open("'"$EVIDENCE_DIR"'/byid.json"));print(len(s) if isinstance(s,list) else 0)')
SVC=$(python3 -c 'import json;s=json.load(open("'"$EVIDENCE_DIR"'/byid.json"));print(",".join(sorted({x.get("resource_attributes",{}).get("service.name","") for x in (s if isinstance(s,list) else [])})))' 2>/dev/null || echo "")

BID_TID=$(python3 -c 'import json;s=json.load(open("'"$EVIDENCE_DIR"'/byid.json"));print(s[0].get("trace_id","") if isinstance(s,list) and s else "")' 2>/dev/null || echo "")

[ "$MS" -ge 1 ] 2>/dev/null || fail "metric request_count not queryable on :9090 ($MS series)"
[ "$LH" -ge 1 ] 2>/dev/null || fail "app log 'card declined' not queryable on :9091 ($LH hits)"
[ -n "$TID" ] || fail "no trace discovered in the window query for service=kaleidoscope-demo — the generator's trace is not observable"
[ "$SC" -ge 1 ] 2>/dev/null || fail "the discovered trace id did not retrieve by-id on :9092 ($SC spans)"
[ "$BID_TID" = "$TID" ] || fail "by-id did not round-trip the discovered trace id (window $TID vs by-id $BID_TID)"
echo "$SVC" | grep -q 'kaleidoscope-demo' || fail "by-id trace service is not kaleidoscope-demo (got '$SVC')"

echo "CRGEN01 satisfied — first-party generator send-to-see: request_count on :9090 ($MS series), 'card declined' log on :9091 ($LH), and the trace DISCOVERED from the window (id $TID) round-trips by-id on :9092 ($SC spans, service kaleidoscope-demo). Our-generator->our-gateway self-compat; trace id observed at runtime, not pinned."
