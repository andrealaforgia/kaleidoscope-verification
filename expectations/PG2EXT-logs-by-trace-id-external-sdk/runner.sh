#!/usr/bin/env bash
# PG2EXT — the "retrieve a trace's logs in one query by its id" capability works
# for a STANDARD EXTERNAL OpenTelemetry SDK, not only the first-party generator.
# This closes PG-2's external-binding criterion: it composes the PG-1 external
# Python app (official opentelemetry-sdk, zero Kaleidoscope code, a log emitted
# INSIDE its span over the real OTLP wire) with the by-trace_id logs query.
#
# After the external app exports its trace, a single query
#   GET :9091/api/v1/logs?trace_id=<the app's own trace id>
# returns that app's in-span log, carrying exactly the app's trace id, and no
# other trace's logs. So a human using a normal external SDK can read a trace's
# correlated logs in one query by id.
#
# Regression net (GREEN-on-arrival): RED if the external app's trace does not
# round-trip its logs by id (the by-id query returns nothing, the wrong trace, or
# the external SDK's trace id is not honoured).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
cp "$(dirname "$0")/../PG1-otlp-external-sdk-trace/pg1_app.py" "$EVIDENCE_DIR/pg1_app.py"

INLINE='
NET="pg2ext-net-$$"; RT="pg2ext-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -v "$DATA_HOST:/data" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19591:9091 -p 19592:9092 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19592/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null | grep -qE "^[0-9]{3}$" && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
docker run --rm --network "$NET" -v "'"$EVIDENCE_DIR"'/pg1_app.py:/pg1_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /pg1_app.py" > "'"$EVIDENCE_DIR"'/app.out" 2> "'"$EVIDENCE_DIR"'/app.err" || { echo "app failed" >&2; tail "'"$EVIDENCE_DIR"'/app.err" >&2; exit 1; }
sleep 2
TID=$(grep -oE "PG1_REPORT=.*" "'"$EVIDENCE_DIR"'/app.out" | sed "s/PG1_REPORT=//" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"trace_id\"])")
echo "EXTERNAL_TRACE_ID=$TID" > "'"$EVIDENCE_DIR"'/trace.txt"
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
curl -s -o "'"$EVIDENCE_DIR"'/by_ext.json" "http://localhost:19591/api/v1/logs?start=${S}&end=${E}&trace_id=${TID}"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" PG2EXT "$INLINE"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
TID = open(evid + "/trace.txt").read().split("=")[1].strip()
if not re.match(r"^[0-9a-f]{32}$", TID):
    fail("the external app did not report a 32-hex trace id (got %r)" % (TID,))
d = json.load(open(evid + "/by_ext.json")); logs = d if isinstance(d, list) else []
app = [l for l in logs if "checkout failed for customer" in str(l.get("body", ""))]
if not app:
    fail("one query by the EXTERNAL app's own trace id returned none of its in-span logs — the by-trace_id retrieval does not work from a standard external SDK")
ids = {l.get("trace_id") for l in logs}
if ids != {TID}:
    fail("the by-trace_id query returned logs from other traces (trace_ids=%r), expected only the external app's %s" % (sorted(ids), TID))
print("PG2EXT satisfied — a standard EXTERNAL OTel SDK's in-span log is retrievable in one query by the app's own trace id (%s) on :9091, scoped to that trace only. The logs-by-trace_id capability is proven cross-SDK, not just first-party." % (TID,))
PY
