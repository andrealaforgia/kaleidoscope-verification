#!/usr/bin/env bash
# LINKEDVIEW — the DATA LINKAGE behind the on-screen linked view, on the endpoint
# the view actually calls. This composes DEMOCAUSE (the demo must be a COHERENT
# failed checkout) and WITHLOGS (one call returns spans+logs together) onto the
# bundled DEMO trace via the combined endpoint: a single
#   GET :9092/api/v1/traces/with_logs?trace_id=<demo trace>
# must return the WHOLE coherent failed-checkout story in ONE response —
# a checkout-shaped Error span (WHERE) AND its single clean cause log (WHY),
# both scoped to the trace, with no orphaned/duplicate cause copies.
#
# This is the data-linkage the view renders. It is NOT the view: the on-screen
# linked view is proven only by the Customer's COLD BROWSER RUN on a clean
# managed instance. Verify this on a FRESH CLEAN instance, never polluted data.
#
# Transition-proof: RED now (the demo trace's failing span is a generic
# GET /api/v1/query_range, not a checkout, and the instance carries orphaned
# cause-log copies), GREEN when the generator emits a checkout-shaped failing
# span with one clean in-span cause log and the combined endpoint returns both.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"

cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
echo "building runtime + generator images from the committed snapshot ..." >&2
docker build -q -t kx-runtime:linkedview -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:linkedview -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="linkedview-net-$$"; RT="linkedview-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19690:9090 -p 19691:9091 -p 19692:9092 kx-runtime:linkedview > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19690/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RT:4317" -e KALEIDOSCOPE_TENANT=acme \
    kx-gen:linkedview > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" \
    || { echo "generator exited non-zero against a LIVE runtime" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
sleep 2

S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
# DISCOVER the demo trace from the window (never the pinned constant).
curl -s -o "$EVIDENCE_DIR/window.json" "http://localhost:19692/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
DEMO_TID=$(python3 -c 'import json;d=json.load(open("'"$EVIDENCE_DIR"'/window.json"));ids=[x.get("trace_id") for x in (d if isinstance(d,list) else []) if x.get("trace_id")];print(ids[0] if ids else "")' 2>/dev/null || echo "")
echo "DEMO_TRACE=$DEMO_TID" > "$EVIDENCE_DIR/demo.txt"
# the ONE call the view makes: the demo trace's spans AND its logs together.
curl -s -o "$EVIDENCE_DIR/with_logs.json" "http://localhost:19692/api/v1/traces/with_logs?trace_id=${DEMO_TID}"
# ALL logs in the window — to catch orphaned / duplicate cause-log copies the
# combined endpoint (scoped) would not show but that pollute the picture.
curl -s -o "$EVIDENCE_DIR/all_logs.json" "http://localhost:19691/api/v1/logs?start=${S}&end=${E}"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
tid = open(evid + "/demo.txt").read().split("=")[1].strip()
if not tid:
    fail("no kaleidoscope-demo trace was discoverable in the window — the demo seed did not produce a trace")
def is_cause(l): return "declined" in str(l.get("body", "")).lower()
def err_msg(s):
    st = s.get("status") or {}
    code = str(st.get("code", "")).lower()
    return (code == "error" or code == "2" or "error" in code), str(st.get("message", "") or "")

obj = json.load(open(evid + "/with_logs.json"))
if not isinstance(obj, dict) or any(k not in obj for k in ("trace_id", "spans", "logs")):
    fail("the view's one call (with_logs) did not return a single {trace_id,spans,logs} object for the demo trace (got %r)" % (type(obj).__name__,))
if obj.get("trace_id") != tid:
    fail("with_logs trace_id %r != the demo trace %r" % (obj.get("trace_id"), tid))
spans = obj.get("spans") or []; logs = obj.get("logs") or []

# WHERE — in the SAME response, a checkout-shaped failing span (coherent), not a
# generic query with a checkout error bolted on.
errspans = [s for s in spans if err_msg(s)[0] and err_msg(s)[1].strip()]
if not errspans:
    have = [(str((s.get("status") or {}).get("code","")), s.get("name")) for s in spans]
    fail("the demo trace %s carries NO Error span with a readable message in the combined response — the view would show no WHERE; got %r" % (tid, have))
es = errspans[0]; name = str(es.get("name") or "")
if "checkout" not in name.lower():
    fail("INCOHERENT view: the failing span the view shows is %r, not a checkout — a newcomer opening the linked view sees a generic operation 'failing' with the message %r, which does not read as a failed checkout. The demo trace must be checkout-shaped." % (name, err_msg(es)[1]))
where = err_msg(es)[1]

# WHY — in the SAME response, the cause log attached to the trace, scoped.
cause = [l for l in logs if is_cause(l)]
if not cause:
    fail("the demo trace's combined response carries NO cause log — the view shows WHERE it failed but not WHY (logs=%d)" % (len(logs),))
lg_ids = {l.get("trace_id") for l in logs}
if lg_ids - {tid}:
    fail("the combined response includes other traces' logs (%r), expected only the demo trace %s" % (sorted(lg_ids), tid))

# COHERENCE — exactly one cause copy on the demo trace, none orphaned anywhere.
on_demo = [l for l in cause if l.get("trace_id") == tid]
if len(on_demo) != 1:
    fail("the demo trace's cause log is not a single clean copy in the view's response — found %d 'card declined' copies (expected exactly 1); duplicates make the view read incoherently" % (len(on_demo),))
al = json.load(open(evid + "/all_logs.json")); alllogs = al if isinstance(al, list) else []
orphaned = [l for l in alllogs if is_cause(l) and not l.get("trace_id")]
if orphaned:
    fail("the instance carries %d ORPHANED 'card declined' cause-log copy/copies (no trace) — stray cause logs unattached to any trace pollute the linked view's data; the cause must belong only to the demo trace" % (len(orphaned),))

print("LINKEDVIEW satisfied — the view's single call (with_logs) on the bundled demo trace returns the WHOLE coherent failed checkout in ONE response: a checkout-shaped Error span (%r, %r) = WHERE, AND its single clean cause log = WHY, both scoped to the trace, no orphaned/duplicate copies. The data linkage the view renders is ready; the on-screen view itself is proven only by the Customer's cold browser run on the clean managed instance." % (name, where))
PY
