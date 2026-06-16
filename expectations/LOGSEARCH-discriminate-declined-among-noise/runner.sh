#!/usr/bin/env bash
# LOGSEARCH — the symptom-path DATA SUBSTRATE (iteration 2): searching logs in
# their own right, over a window, by text-in-body and by severity, DISCRIMINATES
# the one "declined" failure out of realistic noise — and the matched log carries
# its trace_id so the on-screen pivot needs no typed id.
#
# Grounded finding (2026-06-16): the consolidated runtime ALREADY supports
# body_contains (ADR-0055 log-body-text-search) and min_severity (ADR-0052) on its
# logs router, so the symptom-path SEARCH is built; iteration 2's net-new work is
# the on-screen Logs VIEW + the pivot + a noisy bundled demo. This expectation
# guards the discrimination + pivot-data the view rests on.
#
# Driven by the shared noisy emitter (_emitters/noisy_app.py) on a NON-demo service
# so the (default-on) demo overlay does not inject a second declined; the runtime
# is run overlay-OFF here for the same reason.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$(dirname "$0")/../../_emitters/noisy_app.py" "$EVIDENCE_DIR/noisy_app.py"
echo "building runtime image from the committed snapshot ..." >&2
docker build -q -t kx-runtime:logsearch -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.txt" 2>&1

NET="logsearch-net-$$"; RT="logsearch-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
# overlay OFF: this verifies the noisy SEED's discrimination in isolation.
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn \
    -p 19191:9091 -p 19192:9092 kx-runtime:logsearch > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do curl -s -o /dev/null "http://localhost:19192/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -v "$EVIDENCE_DIR/noisy_app.py:/noisy_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/p.log 2>&1 && python /noisy_app.py" \
    > "$EVIDENCE_DIR/noisy.out" 2> "$EVIDENCE_DIR/noisy.err" || { echo "emit failed" >&2; tail "$EVIDENCE_DIR/noisy.err" >&2; exit 1; }
sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
DTID=$(grep -o "NOISY_REPORT=.*" "$EVIDENCE_DIR/noisy.out" | sed "s/NOISY_REPORT=//" | python3 -c "import sys,json;print(json.load(sys.stdin)['declined_trace'])")
echo "DECLINED_TRACE=$DTID" > "$EVIDENCE_DIR/declined.txt"
curl -s -o "$EVIDENCE_DIR/all_logs.json"      "http://localhost:19191/api/v1/logs?start=${S}&end=${E}"
curl -s -o "$EVIDENCE_DIR/bc_declined.json"   "http://localhost:19191/api/v1/logs?start=${S}&end=${E}&body_contains=declined"
curl -s -o "$EVIDENCE_DIR/bc_capital.json"    "http://localhost:19191/api/v1/logs?start=${S}&end=${E}&body_contains=Declined"
# body_regex with the (?i) flag is what the on-screen search box ACTUALLY issues
# (ADR-0056) for its case-insensitive UX — verify the real backend honours it,
# capital query against a lowercase body, so the view is not a mocked-only green.
curl -s -o "$EVIDENCE_DIR/rx_lower.json"   "http://localhost:19191/api/v1/logs?start=${S}&end=${E}&body_regex=%28%3Fi%29declined"
curl -s -o "$EVIDENCE_DIR/rx_capital.json" "http://localhost:19191/api/v1/logs?start=${S}&end=${E}&body_regex=%28%3Fi%29DECLINED"
curl -s -o "$EVIDENCE_DIR/sev_error.json"     "http://localhost:19191/api/v1/logs?start=${S}&end=${E}&min_severity=error"
curl -s -o "$EVIDENCE_DIR/pivot_withlogs.json" "http://localhost:19192/api/v1/traces/with_logs?trace_id=${DTID}"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
def load(n):
    d = json.load(open(evid + "/" + n)); return d if isinstance(d, list) else []
dtid = open(evid + "/declined.txt").read().split("=")[1].strip()
def is_decl(l): return "declined" in str(l.get("body","")).lower()

alll = load("all_logs.json")
declined = [l for l in alll if is_decl(l)]
if len(alll) < 8:
    fail("the noise is too thin (%d logs) — discrimination would be a gimme; need a realistic noisy set" % (len(alll),))
if len(declined) != 1:
    fail("the noisy set does not contain exactly one declined log (found %d) — cannot test discrimination" % (len(declined),))

# TEXT search discriminates the one out of the noise.
bc = load("bc_declined.json")
if len(bc) != 1 or not is_decl(bc[0]):
    fail("body_contains=declined did not pick exactly the one declined log out of %d (got %d) — search returns too much / does not discriminate" % (len(alll), len(bc)))
if not bc[0].get("trace_id"):
    fail("the matched declined log carries no trace_id — the on-screen pivot would need a typed id")
if bc[0].get("trace_id") != dtid:
    fail("the matched declined log's trace_id %r != the emitter's declined trace %r" % (bc[0].get("trace_id"), dtid))

# CASE-SENSITIVE substring (body_contains): capital 'Declined' must not match.
cap = load("bc_capital.json")
if len(cap) != 0:
    fail("body_contains is not case-sensitive as documented — 'Declined' matched %d (expected 0)" % (len(cap),))

# body_regex (?i) — what the on-screen search ACTUALLY issues for case-insensitive
# UX: capital AND lowercase must each find the one lowercase-bodied declined log.
rxl = load("rx_lower.json"); rxc = load("rx_capital.json")
if not (len(rxl) == 1 and is_decl(rxl[0])):
    fail("body_regex=(?i)declined did not return the one declined log (got %d) — the case-insensitive search the view issues does not work on the real backend" % (len(rxl),))
if not (len(rxc) == 1 and is_decl(rxc[0])):
    fail("body_regex=(?i)DECLINED (capital) did not find the lowercase-bodied declined log (got %d) — the view's case-insensitive search would silently empty on a capital query on the REAL backend (mocked-e2e-only green)" % (len(rxc),))

# SEVERITY floor discriminates the error out of the info noise.
sev = load("sev_error.json")
if not (len(sev) == 1 and is_decl(sev[0])):
    fail("min_severity=error did not return exactly the one error (declined) log out of the info noise (got %d)" % (len(sev),))

# PIVOT DATA: the matched log's trace resolves to where->why.
o = json.load(open(evid + "/pivot_withlogs.json"))
spans = o.get("spans") or []; logs = o.get("logs") or []
es = [s for s in spans if str((s.get("status") or {}).get("code","")).lower() == "error"]
if not es:
    fail("pivoting on the declined log's trace shows no Error span (WHERE) — the pivot data is incomplete")
if not any(is_decl(l) for l in logs):
    fail("pivoting on the declined log's trace shows no cause log (WHY) — the pivot data is incomplete")

print("LOGSEARCH satisfied — log search discriminates the failure out of noise and pivots: %d logs, exactly 1 declined; body_contains=declined -> that one (with trace_id %s), case-sensitive ('Declined'->0); body_regex=(?i)declined AND (?i)DECLINED each -> that one (the CASE-INSENSITIVE search the view issues, verified on the REAL backend, not mocked); min_severity=error -> the one error out of INFO noise; the matched log's trace resolves to WHERE + WHY. The on-screen Logs view + pivot rest on this; her cold run is the gate." % (len(alll), dtid))
PY
