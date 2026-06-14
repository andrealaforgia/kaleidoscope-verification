#!/usr/bin/env bash
# PG2BYID — PG-2 criterion 3: given a trace_id, retrieve that trace's correlated
# log(s) in ONE query. The logs query API filters by trace_id, returning only
# the log(s) carrying that exact trace_id and excluding every other trace's logs.
#
# Reuses the PG-1 external OTel app (emits a log INSIDE its active span). It is
# run TWICE in one container, producing two distinct traces A and B, each with
# its own in-span log (identical body, different trace_id). Then:
#   - GET :9091 by trace_id A returns >=1 log, EVERY returned log has trace_id A,
#     and NONE has trace_id B   (filters in A, excludes B);
#   - GET :9091 by trace_id B is the symmetric control (returns B, excludes A);
#   - GET :9091 by a bogus 32-hex trace_id returns zero logs.
#
# Transition-proof: RED now (the trace_id filter is not honoured — the query
# either ignores it and returns both logs, or errors), GREEN when the single
# by-trace_id query returns exactly the matching trace's log(s).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
cp "$(dirname "$0")/../PG1-otlp-external-sdk-trace/pg1_app.py" "$EVIDENCE_DIR/pg1_app.py"

INLINE='
NET="pg2byid-net-$$"; RT="pg2byid-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -v "$DATA_HOST:/data" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19391:9091 -p 19392:9092 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19392/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null | grep -qE "^[0-9]{3}$" && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
docker run --rm --network "$NET" -v "'"$EVIDENCE_DIR"'/pg1_app.py:/pg1_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /pg1_app.py && echo --SEP-- && python /pg1_app.py" > "'"$EVIDENCE_DIR"'/app.out" 2> "'"$EVIDENCE_DIR"'/app.err" || { echo "app failed" >&2; tail "'"$EVIDENCE_DIR"'/app.err" >&2; exit 1; }
sleep 2
TIDS=$(grep -oE "PG1_REPORT=.*" "'"$EVIDENCE_DIR"'/app.out" | sed "s/PG1_REPORT=//" | python3 -c "import sys,json;[print(json.loads(l)[\"trace_id\"]) for l in sys.stdin]")
A=$(echo "$TIDS" | sed -n 1p); B=$(echo "$TIDS" | sed -n 2p)
echo "TRACE_A=$A TRACE_B=$B" > "'"$EVIDENCE_DIR"'/traces.txt"
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
curl -s -o "'"$EVIDENCE_DIR"'/by_a.json"   "http://localhost:19391/api/v1/logs?start=${S}&end=${E}&trace_id=${A}"
curl -s -o "'"$EVIDENCE_DIR"'/by_b.json"   "http://localhost:19391/api/v1/logs?start=${S}&end=${E}&trace_id=${B}"
curl -s -o "'"$EVIDENCE_DIR"'/by_bogus.json" "http://localhost:19391/api/v1/logs?start=${S}&end=${E}&trace_id=00000000000000000000000000000000"
curl -s -o "'"$EVIDENCE_DIR"'/malformed.body" -w "%{http_code}" "http://localhost:19391/api/v1/logs?start=${S}&end=${E}&trace_id=NOT-A-HEX-TRACE-ID-zzz" > "'"$EVIDENCE_DIR"'/malformed.code"
curl -s -o "'"$EVIDENCE_DIR"'/unfiltered.json" "http://localhost:19391/api/v1/logs?start=${S}&end=${E}&body_contains=customer"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" PG2BYID "$INLINE"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
def load(p):
    d = json.load(open(evid + "/" + p))
    return d if isinstance(d, list) else []
txt = open(evid + "/traces.txt").read().split()
A = txt[0].split("=")[1]; B = txt[1].split("=")[1]
hex32 = re.compile(r"^[0-9a-f]{32}$")
if not (hex32.match(A) and hex32.match(B) and A != B):
    fail("precondition: expected two distinct 32-hex trace ids, got A=%r B=%r" % (A, B))
unf = load("unfiltered.json")
if len({l.get("trace_id") for l in unf if "checkout failed for customer" in str(l.get("body",""))}) < 2:
    fail("precondition: the two in-span logs (trace A and B) were not both stored/queryable")
by_a = load("by_a.json"); by_b = load("by_b.json"); bogus = load("by_bogus.json")
a_app = [l for l in by_a if "checkout failed for customer" in str(l.get("body",""))]
if not a_app:
    fail("query by trace_id A returned no correlated log — the by-trace_id filter did not return the matching trace's log")
ids_a = {l.get("trace_id") for l in by_a}
if ids_a != {A}:
    fail("query by trace_id A returned logs from other traces too (trace_ids=%r) — filter not honoured (it must return ONLY trace A's logs)" % (sorted(ids_a),))
b_app = [l for l in by_b if "checkout failed for customer" in str(l.get("body",""))]
ids_b = {l.get("trace_id") for l in by_b}
if not b_app or ids_b != {B}:
    fail("symmetric control failed: query by trace_id B did not return exactly trace B's logs (trace_ids=%r)" % (sorted(ids_b),))
if len(bogus) != 0:
    fail("query by a non-existent trace_id returned %d logs, expected 0 (empty 200)" % (len(bogus),))
code = open(evid + "/malformed.code").read().strip()
body = open(evid + "/malformed.body").read()
raw = "NOT-A-HEX-TRACE-ID-zzz"
if code != "400":
    fail("a malformed trace_id returned HTTP %s, expected 400 (the input is not a 32-hex id)" % (code,))
if "32" not in body or not re.search(r"hex", body, re.I):
    fail("the 400 for a malformed trace_id does not name the expected 32-hex format (body=%r)" % (body[:200],))
if raw in body:
    fail("the 400 echoes the raw malformed input back (no-raw-echo violated): body=%r" % (body[:200],))
print("PG2BYID satisfied — one query by trace_id returns exactly that trace's correlated log(s): by A -> only A (%s), by B -> only B (%s), by a non-existent id -> 0 logs. Cross-trace exclusion holds." % (A, B))
PY
