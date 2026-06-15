#!/usr/bin/env bash
# WITHLOGS — the combined endpoint behind the on-screen linked view: ONE call
# returns a trace's spans AND its correlated logs TOGETHER, server-side, so the
# view shows them together without the user stitching two panels or copying an
# id. This verifies the endpoint CONTRACT only (the data linkage); the on-screen
# linked VIEW is proven separately, only by the Customer's cold browser run.
#
# Uses a KNOWN-CORRELATED trace from the standard external OTel app (PG-1: a log
# emitted INSIDE its span) — NOT the bundled demo, whose coherence is a separate
# track (DEMOCAUSE). So this asserts the mechanism on a clean correlated trace.
#
# GET :9092/api/v1/traces/with_logs?trace_id=<32-hex> ->
#   one JSON object { trace_id, spans:[...], logs:[...] }, scoped to that trace,
#   NO time window. Edge: missing trace_id -> 400; malformed -> 400 (no echo);
#   unknown 32-hex -> 200 with empty spans AND empty logs.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
cp "$(dirname "$0")/../PG1-otlp-external-sdk-trace/pg1_app.py" "$EVIDENCE_DIR/pg1_app.py"

INLINE='
NET="withlogs-net-$$"; RT="withlogs-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -v "$DATA_HOST:/data" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19891:9091 -p 19892:9092 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19892/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null | grep -qE "^[0-9]{3}$" && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
docker run --rm --network "$NET" -v "'"$EVIDENCE_DIR"'/pg1_app.py:/pg1_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /pg1_app.py" > "'"$EVIDENCE_DIR"'/app.out" 2> "'"$EVIDENCE_DIR"'/app.err" || { echo "app failed" >&2; tail "'"$EVIDENCE_DIR"'/app.err" >&2; exit 1; }
sleep 2
TID=$(grep -oE "PG1_REPORT=.*" "'"$EVIDENCE_DIR"'/app.out" | sed "s/PG1_REPORT=//" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"trace_id\"])")
echo "TRACE=$TID" > "'"$EVIDENCE_DIR"'/trace.txt"
curl -s -o "'"$EVIDENCE_DIR"'/with_logs.json"   "http://localhost:19892/api/v1/traces/with_logs?trace_id=${TID}"
curl -s -o "'"$EVIDENCE_DIR"'/missing.body"  -w "%{http_code}" "http://localhost:19892/api/v1/traces/with_logs"               > "'"$EVIDENCE_DIR"'/missing.code"
curl -s -o "'"$EVIDENCE_DIR"'/malformed.body" -w "%{http_code}" "http://localhost:19892/api/v1/traces/with_logs?trace_id=NOT-A-HEX-zzz" > "'"$EVIDENCE_DIR"'/malformed.code"
curl -s -o "'"$EVIDENCE_DIR"'/unknown.json"  -w "%{http_code}" "http://localhost:19892/api/v1/traces/with_logs?trace_id=00000000000000000000000000000000" > "'"$EVIDENCE_DIR"'/unknown.code"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" WITHLOGS "$INLINE"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
tid = open(evid + "/trace.txt").read().split("=")[1].strip()
if not re.match(r"^[0-9a-f]{32}$", tid):
    fail("the external app did not report a 32-hex trace id (got %r)" % (tid,))
# the combined call returns ONE object with spans AND logs together.
obj = json.load(open(evid + "/with_logs.json"))
if not isinstance(obj, dict):
    fail("with_logs did not return a single JSON object {trace_id,spans,logs} (got %s)" % (type(obj).__name__,))
for k in ("trace_id", "spans", "logs"):
    if k not in obj:
        fail("with_logs response missing key %r (got keys %r) — spans and logs must come together in one response" % (k, sorted(obj.keys())))
if obj.get("trace_id") != tid:
    fail("with_logs trace_id %r != the queried trace %r" % (obj.get("trace_id"), tid))
spans = obj.get("spans") or []; logs = obj.get("logs") or []
if not spans:
    fail("with_logs returned no spans for the trace — the trace half of the linked view is missing")
sp_ids = {s.get("trace_id") for s in spans}
if sp_ids - {tid}:
    fail("with_logs spans include other traces (%r), expected only %s" % (sorted(sp_ids), tid))
app_logs = [l for l in logs if "checkout failed for customer" in str(l.get("body", ""))]
if not app_logs:
    fail("with_logs returned no correlated in-span log for the trace — the logs half of the linked view is missing (logs=%d)" % (len(logs),))
lg_ids = {l.get("trace_id") for l in logs}
if lg_ids - {tid}:
    fail("with_logs logs include other traces (%r), expected only %s" % (sorted(lg_ids), tid))
if not re.match(r"^[0-9a-f]{32}$", str(app_logs[0].get("trace_id") or "")):
    fail("with_logs log trace_id is not lowercase-hex (got %r)" % (app_logs[0].get("trace_id"),))
# edge contract
mc = open(evid + "/missing.code").read().strip()
if mc != "400":
    fail("with_logs with NO trace_id returned %s, expected 400" % (mc,))
fc = open(evid + "/malformed.code").read().strip(); fb = open(evid + "/malformed.body").read()
if fc != "400":
    fail("with_logs with a malformed trace_id returned %s, expected 400" % (fc,))
if "NOT-A-HEX-zzz" in fb:
    fail("with_logs 400 echoes the raw malformed input back (no-echo violated): %r" % (fb[:160],))
uc = open(evid + "/unknown.code").read().strip(); uj = json.load(open(evid + "/unknown.json")) if uc == "200" else None
if uc != "200":
    fail("with_logs with an unknown 32-hex trace_id returned %s, expected 200 (empty)" % (uc,))
if not isinstance(uj, dict) or (uj.get("spans") or []) or (uj.get("logs") or []):
    fail("with_logs for an unknown trace did not return 200 with empty spans AND empty logs (got %r)" % (uj,))
print("WITHLOGS satisfied — the combined endpoint returns a trace's spans AND its correlated logs TOGETHER in ONE response, scoped to the trace_id with no window: trace %s -> %d spans + its in-span log, both carrying that trace id. Edge: missing->400, malformed->400 (no echo), unknown->200 empty. The linkage is server-side; the on-screen view is proven only by the Customer's cold browser run." % (tid, len(spans)))
PY
