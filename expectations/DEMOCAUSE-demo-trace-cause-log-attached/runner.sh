#!/usr/bin/env bash
# DEMOCAUSE — the bundled demo's failed-checkout trace carries its CAUSE log,
# so a "trace -> its logs" view on the demo trace shows WHY it failed. This is
# the demo-data prerequisite for the on-screen linked view: the first-party
# generator must emit its failure log ("checkout failed: card declined") INSIDE
# the demo trace's span, so logs-by-trace_id on the demo trace returns the cause.
#
# Discovers the demo trace from the observable window (service=kaleidoscope-demo)
# — never hardcodes the generator's fixed id — then asserts the cause log comes
# back by that trace id with NO window.
#
# Transition-proof: RED now (the demo "card declined" log lands with trace_id
# null, unattached — logs-by-demo-trace returns 0), GREEN when it is emitted
# in-span and returns by the demo trace's id.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"

cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
echo "building runtime + generator images from the committed snapshot ..." >&2
docker build -q -t kx-runtime:democause -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:democause -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="democause-net-$$"; RT="democause-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19790:9090 -p 19791:9091 -p 19792:9092 kx-runtime:democause > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19790/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RT:4317" -e KALEIDOSCOPE_TENANT=acme \
    kx-gen:democause > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" \
    || { echo "generator exited non-zero against a LIVE runtime" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
sleep 2

S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
# DISCOVER the demo trace from the window (never the pinned constant).
curl -s -o "$EVIDENCE_DIR/window.json" "http://localhost:19792/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
DEMO_TID=$(python3 -c 'import json;d=json.load(open("'"$EVIDENCE_DIR"'/window.json"));ids=[x.get("trace_id") for x in (d if isinstance(d,list) else []) if x.get("trace_id")];print(ids[0] if ids else "")' 2>/dev/null || echo "")
echo "DEMO_TRACE=$DEMO_TID" > "$EVIDENCE_DIR/demo.txt"
# the cause log, by the demo trace's id, with NO window.
curl -s -o "$EVIDENCE_DIR/cause_logs.json" "http://localhost:19791/api/v1/logs?trace_id=${DEMO_TID}"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
tid = open(evid + "/demo.txt").read().split("=")[1].strip()
if not tid:
    fail("no kaleidoscope-demo trace was discoverable in the window — the demo seed did not produce a trace")
d = json.load(open(evid + "/cause_logs.json")); logs = d if isinstance(d, list) else []
ids = {l.get("trace_id") for l in logs}
cause = [l for l in logs if "declined" in str(l.get("body", "")).lower()]
if not cause:
    fail("the demo failed-checkout trace %s carries NO cause log — logs-by-trace_id (no window) returned no 'card declined' log; the demo's failure log is not attached to its trace, so a trace->logs view shows no WHY" % (tid,))
if ids != {tid}:
    fail("logs-by-trace_id for the demo trace returned other traces' logs too (%r), expected only %s" % (sorted(ids), tid))
print("DEMOCAUSE satisfied — the bundled demo failed-checkout trace (%s) carries its cause log: logs-by-trace_id with no window returns the '%s' log, scoped to that trace. A trace->its-logs view on the demo trace now shows WHY it failed." % (tid, cause[0].get("body")))
PY
