#!/usr/bin/env bash
# FINDFAIL — finding the failed checkout by its error state must be REAL,
# NON-VACUOUS, and DISCOVERABLE on the demo data the Customer and the on-screen
# view use. Customer-caught gap (2026-06-15): a demo service holding a single
# (error) trace makes "filter to errors" vacuous — any query returns it — and the
# documented help advertised only service+window, so a newcomer could not learn
# the error-find exists at all.
#
# Against the first-party demo seed, this asserts:
#  1. MULTIPLICITY — the demo holds SEVERAL successful traces PLUS the one failed
#     checkout (not a single trace);
#  2. NON-VACUOUS DISTINCTION — filtering that service+window to errors returns
#     EXACTLY the failed checkout, excluding every successful trace;
#  3. DISCOVERABLE — the product's own /help advertises the error-find, so a
#     newcomer finds it without already knowing it exists.
#
# Transition-proof: RED now (demo emits one trace; /help lists service+window
# only). GREEN when the demo seed carries successful traces too AND /help
# advertises the error filter.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"

cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
echo "building runtime + generator images from the committed snapshot ..." >&2
docker build -q -t kx-runtime:findfail -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:findfail -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="findfail-net-$$"; RT="findfail-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19390:9090 -p 19391:9091 -p 19392:9092 kx-runtime:findfail > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19390/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RT:4317" -e KALEIDOSCOPE_TENANT=acme \
    kx-gen:findfail > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" \
    || { echo "generator exited non-zero against a LIVE runtime" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
sleep 2

S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
curl -s -o "$EVIDENCE_DIR/all_traces.json"  "http://localhost:19392/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
curl -s -o "$EVIDENCE_DIR/err_traces.json"  "http://localhost:19392/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}&error=true"
curl -s -o "$EVIDENCE_DIR/help.txt"         "http://localhost:19390/help"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
def load(n):
    d = json.load(open(evid + "/" + n)); return d if isinstance(d, list) else []
def by_trace(spans):
    t = {}
    for s in spans: t.setdefault(s.get("trace_id"), []).append(s)
    return t
def is_err(s): return str((s.get("status") or {}).get("code","")).lower() == "error"

allsp = load("all_traces.json")
traces = by_trace(allsp)
failed = {t for t, ss in traces.items() if any(is_err(s) for s in ss)}
success = set(traces) - failed

# 1. MULTIPLICITY — several successful traces PLUS the one failed checkout.
if len(success) < 2:
    fail("the demo holds %d successful trace(s) and %d failed — find-by-error is VACUOUS without several successful traces to distinguish the failure from (need >=2 successful + 1 failed)" % (len(success), len(failed)))
if len(failed) != 1:
    fail("the demo holds %d failed traces, expected exactly 1 (the failed checkout)" % (len(failed),))
ftid = next(iter(failed))
fspans = traces[ftid]
if not any("checkout" in str(s.get("name","")).lower() for s in fspans if is_err(s)):
    fail("the single failed trace is not checkout-shaped — its error span(s) are %r" % ([s.get("name") for s in fspans if is_err(s)],))

# 2. NON-VACUOUS DISTINCTION — error=true returns EXACTLY the failed checkout.
errsp = load("err_traces.json")
err_ids = {s.get("trace_id") for s in errsp}
if err_ids != {ftid}:
    leaked = err_ids & success
    fail("filtering to errors returned %r, expected only the failed checkout %s%s" % (sorted(err_ids), ftid, (" — it also returned successful traces %r, so it does not distinguish" % sorted(leaked)) if leaked else ""))

# 3. DISCOVERABLE — /help advertises the error-find.
help_txt = open(evid + "/help.txt").read()
traces_examples = re.findall(r"https?://\S*?/api/v1/traces\S*", help_txt)
err_example = [u for u in traces_examples if "error=true" in u]
if not err_example:
    fail("the product's /help does not advertise the error-find — a newcomer reading /help sees traces examples by service+window only (no error= filter), so cannot discover how to find a failure by its error state. /help traces examples: %r" % (traces_examples or "none",))

print("FINDFAIL satisfied — find-by-error on the demo is real, non-vacuous and discoverable: %d successful traces + exactly 1 failed checkout; filtering to errors returns EXACTLY the failed checkout (%s), excluding all successes; and /help advertises the error-find (%s), so a newcomer discovers it without prior knowledge." % (len(success), ftid, err_example[0]))
PY
