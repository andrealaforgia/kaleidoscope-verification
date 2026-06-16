#!/usr/bin/env bash
# IDSEARCH — the identifier-path DATA SUBSTRATE (iteration 2): searching traces on
# screen by service + a STRING attribute (customer.id) must DISCRIMINATE one
# customer's traces out of realistic multi-customer noise — return bea-test's
# traces and NOT everyone's.
#
# Named surface (implementer): GET :9092/api/v1/traces?service=&start=&end=
#   &attr_key=<key>&attr_value=<value> -> only traces with at least one span whose
#   attributes contain attr_key==attr_value (FULL trace, service+window scope);
#   exact string match; attr_key/attr_value both-or-neither (one alone -> 400);
#   absent both -> unchanged.
#
# Transition-proof: RED now (the attr filter is not yet built — it's ignored, so the
# query returns ALL five customers' traces, not just bea-test's). GREEN when the
# filter discriminates. STRING attribute only this iteration (numeric type-fidelity
# deferred). Driven by the shared noisy emitter on a NON-demo service; runtime
# overlay-OFF so the default-on demo overlay does not inject extra traces.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$(dirname "$0")/../../_emitters/noisy_app.py" "$EVIDENCE_DIR/noisy_app.py"
echo "building runtime image from the committed snapshot ..." >&2
docker build -q -t kx-runtime:idsearch -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.txt" 2>&1

NET="idsearch-net-$$"; RT="idsearch-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn \
    -p 19292:9092 kx-runtime:idsearch > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do curl -s -o /dev/null "http://localhost:19292/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -v "$EVIDENCE_DIR/noisy_app.py:/noisy_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/p.log 2>&1 && python /noisy_app.py" \
    > "$EVIDENCE_DIR/noisy.out" 2> "$EVIDENCE_DIR/noisy.err" || { echo "emit failed" >&2; tail "$EVIDENCE_DIR/noisy.err" >&2; exit 1; }
sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
B="http://localhost:19292/api/v1/traces?service=bea-shop&start=${S}&end=${E}"
curl -s -o "$EVIDENCE_DIR/all.json"    "${B}"
curl -s -o "$EVIDENCE_DIR/byattr.json" "${B}&attr_key=customer.id&attr_value=bea-test"
curl -s -o /dev/null -w '%{http_code}' "${B}&attr_key=customer.id" > "$EVIDENCE_DIR/key_only.code"
curl -s -o /dev/null -w '%{http_code}' "${B}&attr_value=bea-test"  > "$EVIDENCE_DIR/val_only.code"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
def load(n):
    d = json.load(open(evid + "/" + n)); return d if isinstance(d, list) else []
def custs(spans): return {(s.get("attributes") or {}).get("customer.id") for s in spans}

allsp = load("all.json")
ac = {c for c in custs(allsp) if c}
if len(ac) < 3:
    fail("the noise has too few distinct customers (%r) — discrimination would be a gimme" % (sorted(ac),))
if "bea-test" not in ac:
    fail("the noisy seed has no bea-test traces to find (customers: %r)" % (sorted(ac),))

# DISCRIMINATION: attr filter returns ONLY bea-test's traces.
ba = load("byattr.json")
bc = {c for c in custs(ba) if c}
if bc != {"bea-test"}:
    leaked = bc - {"bea-test"}
    fail("attr_key=customer.id&attr_value=bea-test returned customers %r, expected only bea-test%s" % (
        sorted(bc), (" — it also returned other customers %r, so it does not discriminate (filter ignored?)" % sorted(leaked)) if leaked else ""))
if not ba:
    fail("the attribute search returned no traces for bea-test — cannot reach her trace")

# EDGES: one of the pair without the other -> 400.
ko = open(evid + "/key_only.code").read().strip()
vo = open(evid + "/val_only.code").read().strip()
if ko != "400":
    fail("attr_key without attr_value returned %s, expected 400 (both-or-neither)" % (ko,))
if vo != "400":
    fail("attr_value without attr_key returned %s, expected 400 (both-or-neither)" % (vo,))

print("IDSEARCH satisfied — trace search by a string attribute discriminates one customer out of noise: %d distinct customers in the window, attr_key=customer.id&attr_value=bea-test returns ONLY bea-test's traces (excluding %s); a key or value alone -> 400. The on-screen identifier search + pivot rest on this; her cold run is the gate." % (len(ac), sorted(ac - {"bea-test"})))
PY
