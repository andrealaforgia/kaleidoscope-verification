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
# KALEIDOSCOPE_DEMO_OVERLAY=0 turns the default-on always-current overlay OFF so this
# expectation verifies the telemetrygen SEED in isolation (else seed + overlay double).
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn \
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
# the cause log (WHY), by the demo trace's id, with NO window.
curl -s -o "$EVIDENCE_DIR/cause_logs.json" "http://localhost:19791/api/v1/logs?trace_id=${DEMO_TID}"
# the trace's spans (WHERE), by id.
curl -s -o "$EVIDENCE_DIR/byid_trace.json" "http://localhost:19792/api/v1/traces/by_id?trace_id=${DEMO_TID}"
# ALL logs in the window — to catch orphaned / duplicate cause-log copies.
curl -s -o "$EVIDENCE_DIR/all_logs.json" "http://localhost:19791/api/v1/logs?start=${S}&end=${E}"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
tid = open(evid + "/demo.txt").read().split("=")[1].strip()
if not tid:
    fail("no kaleidoscope-demo trace was discoverable in the window — the demo seed did not produce a trace")
def is_cause(l): return "declined" in str(l.get("body", "")).lower()

# WHERE — the FAILING span must read as a CHECKOUT (coherent), not a generic
# query with a checkout error bolted on. A newcomer opening it must see a
# checkout that failed.
sp = json.load(open(evid + "/byid_trace.json")); spans = sp if isinstance(sp, list) else []
if not spans:
    fail("the demo trace %s returned no spans by id — cannot show WHERE it failed" % (tid,))
def err_msg(s):
    st = s.get("status") or {}
    code = str(st.get("code", "")).lower()
    return (code == "error" or code == "2" or "error" in code), str(st.get("message", "") or "")
errspans = [s for s in spans if err_msg(s)[0] and err_msg(s)[1].strip()]
if not errspans:
    have = [(str((s.get("status") or {}).get("code","")), s.get("name")) for s in spans]
    fail("the demo trace %s has NO span with Error status AND a readable message — got %r; a newcomer sees no error / no message saying where it failed" % (tid, have))
es = errspans[0]; name = str(es.get("name") or "")
if "checkout" not in name.lower():
    fail("INCOHERENT demo: the failing span is %r, not a checkout — a newcomer opening this trace sees a generic operation 'failing' with the message %r, which doesn't read as a failed checkout. The demo trace must be checkout-shaped (the failing span represents the checkout)." % (name, err_msg(es)[1]))
where = err_msg(es)[1]

# WHY — the cause log is attached to THAT trace (no window).
d = json.load(open(evid + "/cause_logs.json")); logs = d if isinstance(d, list) else []
ids = {l.get("trace_id") for l in logs}
cause_byid = [l for l in logs if is_cause(l)]
if not cause_byid:
    fail("the demo trace %s carries NO cause log by id (no window) — no WHY attached to the trace" % (tid,))
if ids - {tid}:
    fail("logs-by-trace_id for the demo trace returned other traces' logs too (%r), expected only %s" % (sorted(ids), tid))

# COHERENCE across the instance — the cause log is a SINGLE copy attached to the
# demo trace: no orphaned (trace_id null) copies, no duplicates floating around.
al = json.load(open(evid + "/all_logs.json")); alllogs = al if isinstance(al, list) else []
all_cause = [l for l in alllogs if is_cause(l)]
orphaned = [l for l in all_cause if not l.get("trace_id")]
attached = [l for l in all_cause if l.get("trace_id")]
on_demo = [l for l in attached if l.get("trace_id") == tid]
if orphaned:
    fail("the data carries %d ORPHANED cause-log copy/copies (no trace) — a 'card declined' log not attached to any trace; the demo must carry its cause attached to its trace, with no stray copies" % (len(orphaned),))
if len(on_demo) != 1:
    fail("the demo trace's cause log is not a single clean copy — found %d 'card declined' copies on the demo trace (expected exactly 1); duplicates make the demo read incoherently" % (len(on_demo),))
if any(l.get("trace_id") not in (tid, None) for l in all_cause):
    others = sorted({l.get("trace_id") for l in all_cause if l.get("trace_id") not in (tid, None)})
    fail("a 'card declined' cause log is attached to a NON-demo trace too (%r) — the bundled cause must belong only to the demo failed-checkout trace" % (others,))

print("DEMOCAUSE satisfied — the bundled demo tells a COHERENT failed checkout: a checkout-shaped failing span (%r) with Error status and a readable message (%r) = WHERE; its cause log attached to THAT trace, a single clean copy with no orphaned/duplicate copies = WHY (%r). A newcomer opening the demo trace reads a real failed checkout, where and why." % (name, where, cause_byid[0].get("body")))
PY
