#!/usr/bin/env bash
# CRGEN-03 — telemetry the generator emits under tenant acme is queryable under
# acme and ABSENT under any other tenant. Tenant scoping of the generated path,
# observed from the query surface.
#
# Same pillar root: boot the runtime as acme, run the generator, confirm all
# three signals are visible; then restart the runtime bound to tenant-b over the
# same root and confirm the generated telemetry is invisible (0/0/0).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
docker build -q -t kx-runtime:crgen -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:crgen -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="crgen3-net-$$"; RA="crgen3-a-$$"; RB="crgen3-b-$$"; DATA=$(mktemp -d -t crgen3-XXXX)
cleanup() { docker stop "$RA" "$RB" >/dev/null 2>&1 || true; docker rm "$RA" "$RB" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; rm -rf "$DATA"; }
trap cleanup EXIT
docker network create "$NET" >/dev/null

S=$(( $(date -u +%s) - 300 )); E=$(( $(date -u +%s) + 300 ))
metrics() { curl -s "http://localhost:$1/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo NA; }
logs()    { curl -s "http://localhost:$1/api/v1/logs?start=${S}&end=${E}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else 0)' 2>/dev/null || echo NA; }
traces()  { curl -s "http://localhost:$1/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}" | python3 -c 'import sys,json;s=json.load(sys.stdin);print(len(s) if isinstance(s,list) else 0)' 2>/dev/null || echo NA; }
ready()   { for _ in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$1/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" 2>/dev/null)" = "200" ] && return 0; sleep 1; done; return 1; }

docker run -d --name "$RA" --network "$NET" -v "$DATA:/data" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn -p 19390:9090 -p 19391:9091 -p 19392:9092 kx-runtime:crgen > /dev/null
ready 19390 || { echo "runtime(acme) never ready" >&2; docker logs "$RA" >&2 || true; exit 1; }
docker run --rm --network "$NET" -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RA:4317" -e KALEIDOSCOPE_TENANT=acme kx-gen:crgen > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" || { echo "generator failed vs live runtime" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
sleep 2
AM=$(metrics 19390); AL=$(logs 19391); AT=$(traces 19392)
echo "acme_metrics=$AM acme_logs=$AL acme_traces=$AT"
docker stop "$RA" >/dev/null 2>&1 || true; docker rm "$RA" >/dev/null 2>&1 || true

docker run -d --name "$RB" --network "$NET" -v "$DATA:/data" -e KALEIDOSCOPE_TENANT=tenant-b -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn -p 19393:9090 -p 19394:9091 -p 19395:9092 kx-runtime:crgen > /dev/null
ready 19393 || { echo "runtime(tenant-b) never ready" >&2; docker logs "$RB" >&2 || true; exit 1; }
BM=$(metrics 19393); BL=$(logs 19394); BT=$(traces 19395)
echo "tenantb_metrics=$BM tenantb_logs=$BL tenantb_traces=$BT"

fail() { echo "FAIL: $1" >&2; exit 1; }
[ "$AM" -ge 1 ] 2>/dev/null || fail "acme cannot see its own request_count ($AM) — generated telemetry not landing"
[ "$AL" -ge 1 ] 2>/dev/null || fail "acme cannot see its own log ($AL)"
[ "$AT" -ge 1 ] 2>/dev/null || fail "acme cannot see its own trace ($AT)"
[ "$BM" = "0" ] || fail "TENANT-B SEES $BM metric series — cross-tenant leak of generated telemetry"
[ "$BL" = "0" ] || fail "TENANT-B SEES $BL logs — cross-tenant leak"
[ "$BT" = "0" ] || fail "TENANT-B SEES $BT trace spans — cross-tenant leak"
echo "CRGEN03 satisfied — generated telemetry is tenant-scoped: acme sees all three signals (m=$AM l=$AL t=$AT), tenant-b sees none (0/0/0). No cross-tenant leak."
