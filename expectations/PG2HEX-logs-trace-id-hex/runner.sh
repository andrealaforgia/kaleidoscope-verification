#!/usr/bin/env bash
# PG2HEX — PG-2 criterion 5: the logs query API exposes trace_id and span_id as
# lowercase-hex STRINGS, the same shape the traces API already uses, so a log
# and its trace carry byte-for-byte the same id string (correlation by eye and
# by id is possible).
#
# Reuses the PG-1 external OTel app, which emits a log INSIDE the active span.
# After it runs, the log retrieved from :9091 must carry trace_id as a 32-char
# lowercase hex string and span_id as a 16-char lowercase hex string, and those
# strings must EQUAL the same trace's ids retrieved from :9092.
#
# Transition-proof: RED now (the logs API returns trace_id as an integer byte
# array, e.g. [3,171,...]), GREEN when both ids are lowercase-hex strings
# matching the traces API.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
cp "$(dirname "$0")/../PG1-otlp-external-sdk-trace/pg1_app.py" "$EVIDENCE_DIR/pg1_app.py"

INLINE='
NET="pg2hex-net-$$"; RT="pg2hex-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -v "$DATA_HOST:/data" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19291:9091 -p 19292:9092 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19292/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null | grep -qE "^[0-9]{3}$" && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
docker run --rm --network "$NET" -v "'"$EVIDENCE_DIR"'/pg1_app.py:/pg1_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /pg1_app.py" > "'"$EVIDENCE_DIR"'/app.out" 2> "'"$EVIDENCE_DIR"'/app.err" || { echo "app failed" >&2; tail "'"$EVIDENCE_DIR"'/app.err" >&2; exit 1; }
sleep 2
TID=$(grep -oE "PG1_REPORT=.*" "'"$EVIDENCE_DIR"'/app.out" | sed "s/PG1_REPORT=//" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"trace_id\"])")
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
curl -s -o "'"$EVIDENCE_DIR"'/logs.json" "http://localhost:19291/api/v1/logs?start=${S}&end=${E}&body_contains=customer"
curl -s -o "'"$EVIDENCE_DIR"'/byid.json" "http://localhost:19292/api/v1/traces/by_id?trace_id=${TID}"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" PG2HEX "$INLINE"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
logs = json.load(open(evid + "/logs.json")); logs = logs if isinstance(logs, list) else []
spans = json.load(open(evid + "/byid.json")); spans = spans if isinstance(spans, list) else []
applogs = [l for l in logs if "checkout failed for customer" in str(l.get("body", ""))]
if not applogs:
    fail("the in-span log was not retrievable on :9091 (precondition)")
log = applogs[0]
if not spans:
    fail("the trace was not retrievable on :9092 (precondition)")
hex32 = re.compile(r"^[0-9a-f]{32}$"); hex16 = re.compile(r"^[0-9a-f]{16}$")
tid, sid = log.get("trace_id"), log.get("span_id")
if not isinstance(tid, str) or not hex32.match(tid):
    fail("logs API trace_id is not a 32-char lowercase hex string (got %r) — still the byte-array shape" % (tid,))
if not isinstance(sid, str) or not hex16.match(sid):
    fail("logs API span_id is not a 16-char lowercase hex string (got %r)" % (sid,))
trace_tid = spans[0].get("trace_id")
if tid != trace_tid:
    fail("the log's trace_id string %r != the trace's trace_id string %r" % (tid, trace_tid))
span_ids = {s.get("span_id") for s in spans}
if sid not in span_ids:
    fail("the log's span_id %r does not match any span id in its trace %r" % (sid, sorted(span_ids)))
print("PG2HEX satisfied — logs API exposes trace_id (%s) and span_id (%s) as lowercase-hex strings, matching the traces API; the in-span log and its trace share the same id strings." % (tid, sid))
PY
