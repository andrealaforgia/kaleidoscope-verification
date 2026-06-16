#!/usr/bin/env bash
# NOISYDEMO — the always-current OVERLAY-served bundled demo is NOISY and coherent,
# so a newcomer's cold run discriminates a real failure out of noise rather than
# finding a sole planted record. This is the durable demo (ADR-0079, overlay ON,
# NO stored seed) AND iteration 2's "noisy bundled demo" requirement, in one.
#
# Runtime is run overlay-ON (default) with NO seed: the demo is synthesised at read
# time, now-relative, so it is current by construction. Discovers the failing trace
# and its customer.id from the window (never hardcodes the generator's constants).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
echo "building runtime image from the committed snapshot ..." >&2
docker build -q -t kx-runtime:noisydemo -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.txt" 2>&1

NET="noisydemo-net-$$"; RT="noisydemo-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
# overlay ON (default), NO seed: the demo must be present and current from synthesis alone.
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19091:9091 -p 19092:9092 kx-runtime:noisydemo > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do curl -s -o /dev/null "http://localhost:19092/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
sleep 1
NOW=$(date -u +%s); S=$((NOW-3600)); E=$((NOW+60))
T="http://localhost:19092/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}"
L="http://localhost:19091/api/v1/logs?start=${S}&end=${E}"
curl -s -o "$EVIDENCE_DIR/traces.json"     "${T}"
curl -s -o "$EVIDENCE_DIR/logs.json"       "${L}"
curl -s -o "$EVIDENCE_DIR/logs_rx.json"    "${L}&body_regex=%28%3Fi%29DECLINED"
curl -s -o "$EVIDENCE_DIR/logs_sev.json"   "${L}&min_severity=error"

python3 - "$EVIDENCE_DIR" "$S" "$E" <<'PY'
import json, sys, urllib.request
evid, S, E = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def fail(m): print("FAIL: " + m); sys.exit(1)
def load(n):
    d = json.load(open(evid + "/" + n)); return d if isinstance(d, list) else []
def is_decl(x): return "declined" in str(x.get("body","")).lower()
def err(s): return str((s.get("status") or {}).get("code","")).lower() == "error"
def get(u):
    with urllib.request.urlopen(u) as r: return json.loads(r.read().decode())

# ALWAYS-CURRENT (no seed): present from synthesis alone, now-relative.
traces = load("traces.json"); logs = load("logs.json")
if not traces or not logs:
    fail("overlay-served demo (no seed) returned no %s in a recent window — not always-current" % ("traces" if not traces else "logs",))

# NOISY LOGS: many, mostly non-error, exactly one declined.
if len(logs) < 8:
    fail("the demo log set is not noisy enough (%d logs)" % (len(logs),))
decl = [l for l in logs if is_decl(l)]
if len(decl) != 1:
    fail("the demo does not carry exactly one 'declined' log (found %d)" % (len(decl),))
errish = [l for l in logs if str(l.get("severity_text","")).upper() in ("ERROR","FATAL")]
if len(errish) > 1:
    fail("the demo logs are not 'mostly non-error' — %d are error-ish" % (len(errish),))

# SEARCH discriminates on the demo: case-insensitive text + severity floor -> the one.
rx = load("logs_rx.json")
if not (len(rx) == 1 and is_decl(rx[0])):
    fail("body_regex=(?i)DECLINED on the demo did not return exactly the one declined log (got %d)" % (len(rx),))
sev = load("logs_sev.json")
if not (len(sev) == 1 and is_decl(sev[0])):
    fail("min_severity=error on the demo did not return exactly the one error/declined log (got %d)" % (len(sev),))

# NOISY TRACES: several across >=3 customers, exactly one failed checkout.
by_trace = {}
for s in traces: by_trace.setdefault(s.get("trace_id"), []).append(s)
failed = [t for t, ss in by_trace.items() if any(err(s) for s in ss)]
custs = {(s.get("attributes") or {}).get("customer.id") for s in traces} - {None}
if len(by_trace) < 4:
    fail("the demo trace set is not noisy enough (%d traces)" % (len(by_trace),))
if len(custs) < 3:
    fail("the demo traces span too few customers (%r)" % (sorted(custs),))
if len(failed) != 1:
    fail("the demo does not carry exactly one failed trace (found %d)" % (len(failed),))
ftid = failed[0]
fcust = next(((s.get("attributes") or {}).get("customer.id") for s in by_trace[ftid] if (s.get("attributes") or {}).get("customer.id")), None)
if not fcust:
    fail("the demo's failed trace carries no customer.id to search by")

# IDENTIFIER discrimination on the demo: attr -> that customer; + error -> the failure.
base = "http://localhost:19092/api/v1/traces?service=kaleidoscope-demo&start=%d&end=%d" % (S, E)
byattr = get(base + "&attr_key=customer.id&attr_value=" + fcust)
bc = {(s.get("attributes") or {}).get("customer.id") for s in byattr} - {None}
if bc != {fcust}:
    fail("attr search for the failing customer %r returned %r — does not discriminate on the demo" % (fcust, sorted(bc)))
byattr_err = get(base + "&attr_key=customer.id&attr_value=" + fcust + "&error=true")
if {s.get("trace_id") for s in byattr_err} != {ftid}:
    fail("attr=%s + error=true did not narrow to the one failed checkout %s" % (fcust, ftid))

# PIVOT coherence: with_logs -> WHERE + WHY, single cause copy, no orphans.
wl = get("http://localhost:19092/api/v1/traces/with_logs?trace_id=" + ftid)
if not any(err(s) for s in (wl.get("spans") or [])):
    fail("with_logs on the failed demo trace shows no Error span (WHERE)")
cause = [l for l in (wl.get("logs") or []) if is_decl(l)]
if len(cause) != 1:
    fail("with_logs on the failed demo trace does not carry exactly one cause log (got %d)" % (len(cause),))
if [l for l in logs if is_decl(l) and not l.get("trace_id")]:
    fail("the demo carries orphaned (null-trace) declined copies")

print("NOISYDEMO satisfied — the overlay-served demo (no seed, now-relative, always-current) is NOISY and coherent: %d logs (mostly non-error, exactly 1 declined) and %d traces across %d customers with exactly 1 failed checkout (customer.id=%s). Search discriminates: body_regex=(?i)DECLINED and min_severity=error each -> the one log; attr customer.id=%s -> that customer, + error=true -> the one failed checkout, pivoting to WHERE + WHY (single clean cause, no orphans). A newcomer's cold run discriminates a real failure out of noise." % (len(logs), len(by_trace), len(custs), fcust, fcust))
PY
