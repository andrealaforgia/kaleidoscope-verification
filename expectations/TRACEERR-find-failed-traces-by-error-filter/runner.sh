#!/usr/bin/env bash
# TRACEERR — Surface 3 of the linked-view goal: a failed request is FINDABLE and
# distinguishable as failed. The trace listing for a service+window takes an
# error filter: GET :9092/api/v1/traces?service=<svc>&start=&end=&error=true
# returns ONLY the spans of traces that contain at least one Error-status span,
# and returns ALL spans of each such failed trace (so it is reachable in full),
# while EXCLUDING healthy traces in the same service+window. error=false / absent
# is unchanged (returns everything). A malformed error value -> 400 (no echo).
#
# Driven by an external OTel app emitting, under ONE service, a FAILED trace
# (checkout, Error status, + a child) AND a HEALTHY trace (Unset, + a child).
#
# Transition-proof: RED before the filter exists (error=true is ignored, the
# healthy trace is NOT excluded), GREEN once error=true filters to failed traces.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
cp "$(dirname "$0")/s3_app.py" "$EVIDENCE_DIR/s3_app.py"

INLINE='
NET="traceerr-net-$$"; RT="traceerr-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -v "$DATA_HOST:/data" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19792:9092 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19792/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null | grep -qE "^[0-9]{3}$" && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
docker run --rm --network "$NET" -v "'"$EVIDENCE_DIR"'/s3_app.py:/s3_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /s3_app.py" > "'"$EVIDENCE_DIR"'/app.out" 2> "'"$EVIDENCE_DIR"'/app.err" || { echo "app failed" >&2; tail "'"$EVIDENCE_DIR"'/app.err" >&2; exit 1; }
sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
echo "$S $E" > "'"$EVIDENCE_DIR"'/win.txt"
cp "'"$EVIDENCE_DIR"'/app.out" "'"$EVIDENCE_DIR"'/report.txt"
curl -s -o "'"$EVIDENCE_DIR"'/err_true.json"  "http://localhost:19792/api/v1/traces?service=surface3-svc&start=${S}&end=${E}&error=true"
curl -s -o "'"$EVIDENCE_DIR"'/err_false.json" "http://localhost:19792/api/v1/traces?service=surface3-svc&start=${S}&end=${E}&error=false"
curl -s -o "'"$EVIDENCE_DIR"'/err_absent.json" "http://localhost:19792/api/v1/traces?service=surface3-svc&start=${S}&end=${E}"
curl -s -o "'"$EVIDENCE_DIR"'/err_malformed.body" -w "%{http_code}" "http://localhost:19792/api/v1/traces?service=surface3-svc&start=${S}&end=${E}&error=NOTABOOL-zzz" > "'"$EVIDENCE_DIR"'/err_malformed.code"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" TRACEERR "$INLINE"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
rep = None
for ln in open(evid + "/report.txt"):
    if ln.startswith("S3_REPORT="):
        rep = json.loads(ln[len("S3_REPORT="):])
if not rep or not rep.get("failed") or not rep.get("healthy"):
    fail("the external app did not report both a failed and a healthy trace id (got %r)" % (rep,))
failed, healthy = rep["failed"], rep["healthy"]
if failed == healthy:
    fail("the emitter produced one trace, not two distinct ones — cannot test exclusion")

def spans(name):
    d = json.load(open(evid + "/" + name))
    if not isinstance(d, list):
        fail("listing %s did not return a JSON array (got %r)" % (name, d))
    return d
def tids(ss): return {s.get("trace_id") for s in ss}

# error=true: ONLY the failed trace, and ALL of its spans; healthy EXCLUDED.
et = spans("err_true.json")
et_ids = tids(et)
if healthy in et_ids:
    fail("error=true did NOT exclude the healthy trace — a 'show me failures' query returns a trace with no error span, so failed traces are not distinguishable")
if et_ids != {failed}:
    fail("error=true returned trace ids %r, expected only the failed trace %s" % (sorted(et_ids), failed))
failed_all = [s for s in spans("err_absent.json") if s.get("trace_id") == failed]
if len(et) < len(failed_all) or len(et) == 0:
    fail("error=true did not return ALL spans of the failed trace (got %d of the trace's %d) — the failed trace is not reachable in full" % (len(et), len(failed_all)))
if not any(str((s.get("status") or {}).get("code","")).lower() == "error" for s in et):
    fail("error=true result carries no Error-status span — the failed trace is not actually surfaced as failed")

# error=false and absent: unchanged — BOTH traces present.
for nm in ("err_false.json", "err_absent.json"):
    ids = tids(spans(nm))
    if failed not in ids or healthy not in ids:
        fail("%s should be unchanged and include BOTH traces, got %r" % (nm, sorted(ids)))

# malformed error -> 400, no echo.
mc = open(evid + "/err_malformed.code").read().strip()
mb = open(evid + "/err_malformed.body").read()
if mc != "400":
    fail("a malformed error value returned %s, expected 400" % (mc,))
if "NOTABOOL-zzz" in mb:
    fail("the 400 for a malformed error value echoes the raw input back (no-echo violated): %r" % (mb[:160],))

print("TRACEERR satisfied — the error filter makes a failed request findable AND distinguishable: error=true returns ONLY the failed checkout trace (all %d of its spans, Error status present) and EXCLUDES the healthy trace in the same service+window; error=false/absent are unchanged (both traces); a malformed error value -> 400 with no echo." % (len(et),))
PY
