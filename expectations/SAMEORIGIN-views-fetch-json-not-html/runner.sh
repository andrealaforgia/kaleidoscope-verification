#!/usr/bin/env bash
# SAMEORIGIN — every on-screen view's data fetch, issued against the view's OWN
# origin (:9090, where the SPA is served, ADR-0078), must return the signal's JSON,
# NOT the SPA HTML page. This closes the class of bug that has now escaped
# automation TWICE and been caught only by the Customer: a frontend fetch resolving
# to HTML where it expects JSON ("Unexpected token '<'"), because a route is not
# merged same-origin and falls through to the SPA catch-all.
#
# Why mocked e2es + backend-substrate checks miss it: the e2e MOCKS the data (the
# view renders), the substrate check hits the signal's OWN port (:9091/:9092 return
# JSON) — but nothing exercises the served VIEW's real fetch on :9090. This does.
#
# Transition-proof: RED while the LOGS routes are not merged on :9090 (the Logs
# view's /api/v1/logs fetch returns HTML); GREEN when every view's data route on
# :9090 returns JSON.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
echo "building runtime image from the committed snapshot ..." >&2
docker build -q -t kx-runtime:sameorigin -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.txt" 2>&1

NET="sameorigin-net-$$"; RT="sameorigin-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
# overlay default-on (the deployed/cutover config); routing is independent of it.
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19090:9090 kx-runtime:sameorigin > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do curl -s -o /dev/null "http://localhost:19090/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready (or :9090 not serving)" >&2; docker logs "$RT" >&2 || true; exit 1; }

NOW=$(date -u +%s); S=$((NOW-3600)); E=$((NOW+60))
O="http://localhost:19090"
probe() { # name url -> writes "name|content_type|first40" to routes.txt
    local name="$1" url="$2"
    local ct first
    ct=$(curl -s -o "$EVIDENCE_DIR/${name}.body" -w "%{content_type}" "$url")
    first=$(head -c 40 "$EVIDENCE_DIR/${name}.body" | tr -d '\n')
    echo "${name}|${ct}|${first}" >> "$EVIDENCE_DIR/routes.txt"
}
: > "$EVIDENCE_DIR/routes.txt"
# Each on-screen view's REAL data fetch, on the view's own origin :9090:
probe metrics "${O}/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s"
probe logs    "${O}/api/v1/logs?start=${S}&end=${E}"
probe logs_rx "${O}/api/v1/logs?start=${S}&end=${E}&body_regex=%28%3Fi%29declined"
probe traces  "${O}/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
probe with_logs "${O}/api/v1/traces/with_logs?trace_id=4bf92f3577b34da6a3ce929d0e0e4736"

python3 - "$EVIDENCE_DIR" <<'PY'
import sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
rows = [l.rstrip("\n").split("|", 2) for l in open(evid + "/routes.txt") if l.strip()]
if len(rows) < 5:
    fail("expected 5 view data routes probed, got %d — the probe did not complete" % (len(rows),))
bad = []
for name, ct, first in rows:
    # the route must return the signal's JSON. Anything else — the SPA HTML page
    # (the deployed symptom), an empty/404 body (the runtime not merging the route
    # same-origin), or any non-JSON — is the bug the view chokes on.
    ok = ("application/json" in ct) and (first.lstrip()[:1] in ("[", "{"))
    if not ok:
        why = "SPA HTML" if ("text/html" in ct or first.lower().lstrip().startswith("<!doctype")) else ("empty/non-JSON (route not served same-origin)" if not ct or not first else "non-JSON")
        bad.append((name, ct or "(none)", why))
if bad:
    lines = "; ".join("%s -> %s [%s]" % (n, ct, why) for n, ct, why in bad)
    fail("on its own origin (:9090), the data fetch for these view(s) does NOT return the signal's JSON, so the view throws 'Unexpected token <' / cannot render: %s. The route is not merged same-origin (it falls through to the SPA catch-all on the deployed stack, or is simply not served on :9090 here). Traces/metrics ARE merged; the logs route is the gap." % (lines,))
print("SAMEORIGIN satisfied — every on-screen view's data fetch on its own origin (:9090) returns the signal's JSON: " + ", ".join("%s=%s" % (n, ct) for n, ct, _ in rows) + ". The same-origin glue each view actually uses is exercised against the real backend, so the HTML/empty-where-JSON-expected class is caught here, not only by the Customer's cold run.")
PY
