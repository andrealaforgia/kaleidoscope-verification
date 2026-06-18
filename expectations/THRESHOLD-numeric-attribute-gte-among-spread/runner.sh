#!/usr/bin/env bash
# THRESHOLD — iteration 3, half 2: a numeric >= filter on a trace attribute compares
# NUMERICALLY, not lexically. Over the digit/decimal-boundary spread, attr_gte=100
# must return exactly {100,250,250.50,500} and EXCLUDE {9,90,99.99} — including the
# Customer's anti-lexical probe 99.99 ("99.99" sorts above "100" as strings, 9>1, so
# a string comparison would wrongly include it).
#
# Named surface (implementer): GET :9092/api/v1/traces?service=&start=&end=
#   &attr_key=payment.amount&attr_gte=<number>; attr_key/attr_gte both-or-neither
#   (one alone -> 400); composes with existing filters.
#
# Transition-proof: RED until type fidelity lands (values are strings today, so the
# numeric filter cannot discriminate — it is absent/ignored or would compare
# lexically). GREEN when attr_gte filters numerically. Overlay-OFF; non-demo service.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$(dirname "$0")/../../_emitters/numeric_app.py" "$EVIDENCE_DIR/numeric_app.py"
echo "building runtime image from the committed snapshot ..." >&2
docker build -q -t kx-runtime:threshold -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.txt" 2>&1

NET="threshold-net-$$"; RT="threshold-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn \
    -p 19692:9092 kx-runtime:threshold > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do curl -s -o /dev/null "http://localhost:19692/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -v "$EVIDENCE_DIR/numeric_app.py:/numeric_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/p.log 2>&1 && python /numeric_app.py" \
    > "$EVIDENCE_DIR/num.out" 2> "$EVIDENCE_DIR/num.err" || { echo "emit failed" >&2; tail "$EVIDENCE_DIR/num.err" >&2; exit 1; }
sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
B="http://localhost:19692/api/v1/traces?service=bea-shop&start=${S}&end=${E}"
grep -o "NUM_REPORT=.*" "$EVIDENCE_DIR/num.out" | sed "s/NUM_REPORT=//" > "$EVIDENCE_DIR/report.json"
curl -s -o "$EVIDENCE_DIR/gte100.json"  "${B}&attr_key=payment.amount&attr_gte=100"
curl -s -o /dev/null -w '%{http_code}' "${B}&attr_key=payment.amount" > "$EVIDENCE_DIR/key_only.code"
curl -s -o /dev/null -w '%{http_code}' "${B}&attr_gte=100"            > "$EVIDENCE_DIR/gte_only.code"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
rep = json.load(open(evid + "/report.json"))
by_amount = rep["by_amount"]                 # {"9": tid, "90": tid, "99.99": tid, ...}
tid_to_amount = {tid: float(a) for a, tid in by_amount.items()}
def load(n):
    d = json.load(open(evid + "/" + n)); return d if isinstance(d, list) else []

gte = load("gte100.json")
got_tids = {s.get("trace_id") for s in gte} & set(tid_to_amount)
got_amounts = sorted({tid_to_amount[t] for t in got_tids})
want_at_or_above = sorted(a for a in tid_to_amount.values() if a >= 100)   # {100,250,250.5,500}
below = sorted(a for a in tid_to_amount.values() if a < 100)               # {9,90,99.99}

leaked = [a for a in got_amounts if a < 100]
missing = [a for a in want_at_or_above if a not in got_amounts]
if leaked or missing:
    detail = ""
    if 99.99 in leaked:
        detail = " — 99.99 leaked in, the lexical bug ('99.99' > '100' as strings); the comparison is not numeric"
    fail("attr_gte=100 did not filter NUMERICALLY: returned amounts %r, expected exactly %r (excluding %r). leaked-below=%r missing=%r%s" % (
        got_amounts, want_at_or_above, below, leaked, missing, detail))

# both-or-neither edge
ko = open(evid + "/key_only.code").read().strip()
go = open(evid + "/gte_only.code").read().strip()
if ko != "400":
    fail("attr_key=payment.amount without attr_gte returned %s, expected 400 (both-or-neither)" % (ko,))
if go != "400":
    fail("attr_gte=100 without attr_key returned %s, expected 400 (both-or-neither)" % (go,))

print("THRESHOLD satisfied — numeric >= filters NUMERICALLY across the digit/decimal boundary: attr_key=payment.amount&attr_gte=100 returns exactly %r and excludes %r (incl. the 99.99 anti-lexical case); attr_key or attr_gte alone -> 400. The on-screen numeric search rests on this; her cold run is the gate." % (want_at_or_above, below))
PY
