#!/usr/bin/env bash
# Q03 — query-api `step` is accepted and ignored (raw points, no
# re-stepping) at v0.
#
# The Prometheus query_range contract uses `step` to control sample
# resolution. query-api pins that route (ADR-0042) but at v0 returns the
# raw stored points and ignores `step` entirely (DD5; the field is
# `#[allow(dead_code)] step: Option<String>` at
# crates/query-api/src/lib.rs:144). This is DISCLOSED in the doc comment,
# so it is not a false claim — it is a truthful v0 limitation. Q03 pins
# the observable consequence and guards it: two query_range calls over
# the SAME window differing ONLY in `step` return BYTE-IDENTICAL
# `.data.result`.
#
# Given one OTLP metric ingested via the gateway into Pulse and read back
# through query-api
# When query_range is called over a fixed [start,end] window first with
# step=15s and then with step=3600s
# Then both succeed and their `.data.result` payloads are identical —
# proving `step` has no effect on the returned series at v0.
#
# Integrator caveat (recorded honestly, not filed as a defect): a
# Prometheus-compatible client that relies on `step` to bucket/downsample
# will receive raw points regardless. Disclosed by DD5; flips when v0
# implements re-stepping.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="q03-gw-$$"
QAPI_NAME="q03-qapi-$$"
cleanup() {
    docker stop --time 5 "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Start gateway (unique high port, N27).
docker run --rm -d --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14333:4318 "$GW_IMAGE" > /dev/null
SAW=""
for _ in $(seq 1 30); do
    docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2

# 2. Ingest one metric (counter "gen").
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14333 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 --otlp-attributes service.name=\"q03-pilot\" \
    > /tmp/tg.out 2> /tmp/tg.err || { echo "telemetrygen failed" >&2; cat /tmp/tg.err >&2; exit 1; }

# 3. Flush Pulse.
docker stop --time 10 "$GW_NAME" > /dev/null
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# 4. Start query-api on the same /data.
docker run --rm -d --name "$QAPI_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19098:9090 "$QAPI_IMAGE" > /dev/null
sleep 3

# 5. ONE fixed window; query twice varying ONLY step.
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(date -u +%s)
echo "window_start=$START window_end=$END"
curl -sS "http://localhost:19098/api/v1/query_range?query=gen&start=${START}&end=${END}&step=15s" \
    > "'"$EVIDENCE_DIR"'/response-step-15s.json"
curl -sS "http://localhost:19098/api/v1/query_range?query=gen&start=${START}&end=${END}&step=3600s" \
    > "'"$EVIDENCE_DIR"'/response-step-3600s.json"
docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
echo "---15s head---"; head -c 300 "'"$EVIDENCE_DIR"'/response-step-15s.json"; echo
echo "---3600s head---"; head -c 300 "'"$EVIDENCE_DIR"'/response-step-3600s.json"; echo
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" Q03 "$INLINE"

R15="$EVIDENCE_DIR/response-step-15s.json"
R3600="$EVIDENCE_DIR/response-step-3600s.json"

# Both must succeed.
for f in "$R15" "$R3600"; do
    s=$(jq -r '.status' "$f" 2>/dev/null)
    [[ "$s" == "success" ]] || { echo "FAIL: $f status=$s (expected success)" >&2; cat "$f" >&2; exit 1; }
done
# Non-empty series (the metric must actually be present, else "identical
# empty" would pass vacuously).
N15=$(jq -r '.data.result | length' "$R15")
[[ "$N15" -gt 0 ]] || { echo "FAIL: empty result at step=15s; ingest/read precondition unmet (cannot test step ignored vacuously)" >&2; cat "$R15" >&2; exit 1; }

# Canonical (sorted-key) comparison of .data.result. Identical => step
# had no effect.
CANON15=$(jq -S '.data.result' "$R15")
CANON3600=$(jq -S '.data.result' "$R3600")
if [[ "$CANON15" == "$CANON3600" ]]; then
    NSAMP=$(jq -r '[.data.result[].values | length] | add' "$R15")
    echo "OK — query-api step is accepted and IGNORED at v0: query_range over a fixed window returned BYTE-IDENTICAL .data.result for step=15s and step=3600s (${N15} series, ${NSAMP} raw sample(s); no re-stepping, DD5). Disclosed v0 behaviour; this is the regression guard."
else
    echo "DIVERGENCE: .data.result differs between step=15s and step=3600s — step now affects the series. query-api may have implemented re-stepping; Q03 must be re-framed (the v0 'step ignored' contract no longer holds)." >&2
    diff <(echo "$CANON15") <(echo "$CANON3600") | head -40 >&2
    exit 1
fi
