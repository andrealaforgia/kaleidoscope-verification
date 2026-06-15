#!/usr/bin/env bash
# HELPRUN — the getting-started help is usable COLD: starting only from GET /help
# on a running, demo-seeded stack, a newcomer copies each printed example
# VERBATIM and gets back that signal's actual data — for all of metrics, logs,
# traces-by-service-window, and a single-trace-by-id — with no example landing on
# a success-looking HTML page.
#
# This STRENGTHENS the older "the help text exists" check (FIXB1) to the PO's
# re-opened Definition of Done: each example, followed as written, returns data.
#
# How the examples are run truly verbatim: the example-runner container SHARES
# the runtime's network namespace (--network container:<rt>), so the examples'
# own "http://localhost:9090|9091|9092/..." addresses resolve to the runtime's
# real per-signal services. Nothing is rewritten — the exact host/port/path the
# help prints is what gets called. This is also what a newcomer experiences:
# "the stack is on my localhost".
#
# Transition-proof RED at the current tree: the logs / traces / by-id examples
# all point at the metrics address, so verbatim they return the dashboard HTML
# page (HTTP 200, no data); and the example values/time window don't match the
# demo data, so even the metrics example returns nothing. GREEN when every
# printed example, run verbatim against the seeded demo, returns its signal's
# data as JSON (not HTML, not empty).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"

cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
echo "building runtime + generator images from the committed snapshot ..." >&2
docker build -q -t kx-runtime:helprun -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:helprun -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="helprun-net-$$"; RT="helprun-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null

docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19490:9090 -p 19491:9091 -p 19492:9092 kx-runtime:helprun > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19490/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

# seed the canonical demo data (all three signals) via the first-party generator
docker run --rm --network "$NET" \
    -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RT:4317" -e KALEIDOSCOPE_TENANT=acme \
    kx-gen:helprun > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" \
    || { echo "generator exited non-zero against a LIVE runtime" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
sleep 2

# fetch the help exactly as a newcomer would
curl -s -o "$EVIDENCE_DIR/help.txt" "http://localhost:19490/help"

# pull every example command's URL out of the help text, in order
grep -oE "https?://[^'\" ]+" "$EVIDENCE_DIR/help.txt" > "$EVIDENCE_DIR/urls.txt" || true

# run each example URL VERBATIM from inside the runtime's own network namespace,
# so the example's localhost:<port> hits the matching per-signal service
run_verbatim() {
    local url="$1" out="$2"
    docker run --rm --network "container:$RT" curlimages/curl:latest \
        -s -w '\n__HTTP__%{http_code}__CT__%{content_type}' "$url" > "$out" 2>/dev/null || true
}

i=0
while IFS= read -r url; do
    [ -n "$url" ] || continue
    i=$((i+1))
    case "$url" in
        *"/api/v1/query_range"*)      run_verbatim "$url" "$EVIDENCE_DIR/ex_metrics.out" ;;
        *"/api/v1/traces/by_id"*)     run_verbatim "$url" "$EVIDENCE_DIR/ex_byid.out" ;;
        *"/api/v1/logs"*)             run_verbatim "$url" "$EVIDENCE_DIR/ex_logs.out" ;;
        *"/api/v1/traces"*)           run_verbatim "$url" "$EVIDENCE_DIR/ex_traces.out" ;;
    esac
done < "$EVIDENCE_DIR/urls.txt"
docker logs "$RT" > "$EVIDENCE_DIR/runtime.stderr.txt" 2>&1 || true

python3 - "$EVIDENCE_DIR" <<'PY'
import json, re, sys, os
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)

def parse(name):
    p = os.path.join(evid, name)
    if not os.path.exists(p):
        return None
    raw = open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"__HTTP__(\d{3})__CT__(.*)$", raw, re.S)
    if not m:
        return {"code": None, "ctype": "", "body": raw}
    code = m.group(1); ctype = m.group(2).strip()
    body = raw[:m.start()]
    return {"code": code, "ctype": ctype, "body": body}

help_txt = open(os.path.join(evid, "help.txt"), encoding="utf-8", errors="replace").read()
# the four examples must be present in /help to begin with
for needle in ["/api/v1/query_range", "/api/v1/logs", "/api/v1/traces", "/api/v1/traces/by_id"]:
    if needle not in help_txt:
        fail("GET /help does not list the %s example — the four examples must all be present" % needle)

def looks_like_html(d):
    if "html" in (d["ctype"] or "").lower():
        return True
    head = (d["body"] or "").lstrip()[:200].lower()
    return head.startswith("<!doctype") or head.startswith("<html") or "<title>" in head

def require_signal(name, label, check):
    d = parse(name)
    if d is None:
        fail("the %s example was not present/extractable from /help" % label)
    if d["code"] != "200":
        fail("the %s example, run verbatim, returned HTTP %s (expected 200 with data)" % (label, d["code"]))
    if looks_like_html(d):
        fail("the %s example, run verbatim, returned a success-looking HTML page (content-type %r) instead of %s data — it points at the wrong address" % (label, d["ctype"], label))
    try:
        payload = json.loads(d["body"])
    except Exception:
        fail("the %s example, run verbatim, did not return JSON data (first 120 chars: %r)" % (label, (d["body"] or "")[:120]))
    n = check(payload)
    if n < 1:
        fail("the %s example, run verbatim, returned 0 %s rows — a newcomer copying it as written gets no data" % (label, label))
    return n

m = require_signal("ex_metrics.out", "metrics",
                   lambda p: len(p.get("data", {}).get("result", [])) if isinstance(p, dict) else 0)
l = require_signal("ex_logs.out", "logs",
                   lambda p: len(p) if isinstance(p, list) else 0)
t = require_signal("ex_traces.out", "traces",
                   lambda p: len(p) if isinstance(p, list) else 0)
b = require_signal("ex_byid.out", "single-trace-by-id",
                   lambda p: len(p) if isinstance(p, list) else 0)

print("HELPRUN satisfied — every /help example, copied verbatim against the demo-seeded stack, returns its signal's data: metrics %d series, logs %d, traces %d, single-trace-by-id %d spans. No example landed on an HTML dead end." % (m, l, t, b))
PY
