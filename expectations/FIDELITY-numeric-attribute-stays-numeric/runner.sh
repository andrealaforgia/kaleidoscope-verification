#!/usr/bin/env bash
# FIDELITY — iteration 3, half 1: a numeric attribute the app emits as a NUMBER
# comes back as a NUMBER, not a string. The platform currently coerces numeric
# attribute values to strings (int 42 -> "42"), so this is RED until the
# type-fidelity fix. This is the foundation the numeric threshold search rests on:
# a >= comparison can only be numeric (not a lexical string sort) if the value is
# genuinely a number end to end (ingest -> store -> query -> JSON).
#
# Driven by the shared numeric emitter (payment.amount across a digit-boundary
# spread). Overlay-OFF; non-demo service.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$(dirname "$0")/../../_emitters/numeric_app.py" "$EVIDENCE_DIR/numeric_app.py"
echo "building runtime image from the committed snapshot ..." >&2
docker build -q -t kx-runtime:fidelity -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.txt" 2>&1

NET="fidelity-net-$$"; RT="fidelity-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=warn \
    -p 19592:9092 kx-runtime:fidelity > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do curl -s -o /dev/null "http://localhost:19592/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

docker run --rm --network "$NET" -v "$EVIDENCE_DIR/numeric_app.py:/numeric_app.py:ro" -e OTEL_HTTP_ENDPOINT="http://$RT:4318" python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/p.log 2>&1 && python /numeric_app.py" \
    > "$EVIDENCE_DIR/num.out" 2> "$EVIDENCE_DIR/num.err" || { echo "emit failed" >&2; tail "$EVIDENCE_DIR/num.err" >&2; exit 1; }
sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
curl -s -o "$EVIDENCE_DIR/traces.json" "http://localhost:19592/api/v1/traces?service=bea-shop&start=${S}&end=${E}"

python3 - "$EVIDENCE_DIR" <<'PY'
import json, sys
evid = sys.argv[1]
def fail(m): print("FAIL: " + m); sys.exit(1)
traces = json.load(open(evid + "/traces.json")); traces = traces if isinstance(traces, list) else []
vals = [(s.get("attributes") or {}).get("payment.amount") for s in traces if (s.get("attributes") or {}).get("payment.amount") is not None]
if not vals:
    fail("no payment.amount attribute came back on the checkout traces — nothing to check")
# Each value must be a JSON NUMBER (int/float in Python after json.load), not a string.
stringy = [v for v in vals if not isinstance(v, (int, float)) or isinstance(v, bool)]
if stringy:
    fail("payment.amount comes back as a STRING, not a number: %r. The platform coerces numeric attribute values to strings; a numeric >= comparison cannot be genuine until this is fixed." % (sorted(set(map(repr, stringy)))[:6],))
print("FIDELITY satisfied — a numeric attribute stays numeric end to end: payment.amount values %r come back as JSON numbers (not strings), so a >= comparison can be genuinely numeric." % (sorted(set(vals)),))
PY
