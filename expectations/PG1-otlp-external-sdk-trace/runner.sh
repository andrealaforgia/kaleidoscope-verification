#!/usr/bin/env bash
# PG1 — OTLP compatibility proven by a REAL EXTERNAL app (official OTel Python
# SDK, ZERO Kaleidoscope code) over the real OTLP wire. The repeatable,
# committed black-box regression net for the Customer's ad-hoc proof
# (product goal PG-1, agreed with the PO).
#
# A parent+child trace with a span attribute customer.id="bea-test" is exported
# by the external app to the consolidated runtime's OTLP/HTTP ingest (:4318),
# then retrieved by trace-id from the trace query API (:9092) and checked
# against exactly what the app sent:
#   1. external official SDK, no Kaleidoscope code, real OTLP wire.
#   2. parent+child tree survives: child.parent_span_id == root.span_id (and
#      both match the app's span ids).
#   3. customer.id="bea-test" present in the retrieved child span attributes.
#   4. retrieved start/end nanos EXACTLY round-trip the app-sent values; the
#      parent window encloses the child.
# Bonus (non-blocking, PG-2 seed): a log emitted inside the active span is
# retrievable on :9091 carrying the same trace_id.
#
# Generator-independent: uses `make up`-equivalent runtime only.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

# stage the external app next to the evidence so the container can mount it.
cp "$(dirname "$0")/pg1_app.py" "$EVIDENCE_DIR/pg1_app.py"

INLINE='
NET="pg1-net-$$"; RT="pg1-rt-$$"
docker network create "$NET" >/dev/null
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$RT" --network "$NET" -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19160:9092 -p 19161:9091 "$CRT_IMAGE" > /dev/null

RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19160/api/v1/traces?service=x&start=$((RNOW-300))&end=${RNOW}" 2>/dev/null)" = "200" ] && { READY=ok; break; }
    sleep 1
done
[ "${READY:-}" = ok ] || { echo "runtime never ready on :9092" >&2; docker logs "$RT" >&2 || true; exit 1; }

# the EXTERNAL app: official OTel SDK only, exports to the runtime over OTLP/HTTP.
docker run --rm --network "$NET" \
    -v "'"$EVIDENCE_DIR"'/pg1_app.py:/pg1_app.py:ro" \
    -e OTEL_HTTP_ENDPOINT="http://$RT:4318" \
    python:3-slim \
    sh -c "pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-http >/tmp/pip.log 2>&1 && python /pg1_app.py" \
    > "'"$EVIDENCE_DIR"'/app.out" 2> "'"$EVIDENCE_DIR"'/app.err" \
    || { echo "external app failed" >&2; tail -20 "'"$EVIDENCE_DIR"'/app.err" >&2; exit 1; }
cat "'"$EVIDENCE_DIR"'/app.out"

sleep 2
TID=$(grep -oE "PG1_REPORT=.*" "'"$EVIDENCE_DIR"'/app.out" | sed "s/PG1_REPORT=//" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"trace_id\"])")
echo "trace_id=$TID"
echo "byid_code=$(curl -s -o "'"$EVIDENCE_DIR"'/byid.json" -w "%{http_code}" "http://localhost:19160/api/v1/traces/by_id?trace_id=$TID")"
LEND=$(( $(date -u +%s) + 120 ))
echo "logs_code=$(curl -s -o "'"$EVIDENCE_DIR"'/logs.json" -w "%{http_code}" "http://localhost:19161/api/v1/logs?start=$((RNOW-300))&end=${LEND}")"
docker logs "$RT" > "'"$EVIDENCE_DIR"'/runtime.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" PG1 "$INLINE"

OUT="$EVIDENCE_DIR/PG1.stdout.txt"
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }
BC=$(grep -oE 'byid_code=[0-9]+' "$OUT" | tail -1 | cut -d= -f2)
[ "$BC" = "200" ] || fail "by-id retrieval not 200 (got $BC); the external app's trace did not land or is not retrievable"

python3 "$(dirname "$0")/pg1_assert.py" "$EVIDENCE_DIR" --bonus
echo "PG1 GREEN — external OTel SDK round-trips through the real OTLP wire; the Customer's ad-hoc proof is now a repeatable committed black-box net."
