#!/usr/bin/env bash
# Q06 — query-api HONOURS label matchers (they filter the series),
# the direct contrast to Q03 (where `step` is ignored).
#
# A label matcher is applied in keep_row over the merged label set
# (resource_attributes ∪ point.attributes ∪ {__name__}), BEFORE to_matrix.
# So a matcher that the row satisfies keeps it, and a matcher it does not
# satisfy drops it. We use the always-present, authoritative __name__
# label: `gen{__name__="gen"}` returns the series, `gen{__name__="<no>"}`
# returns empty. The same mechanism applies to attribute labels.
#
# Given one OTLP metric `gen` ingested via the gateway into Pulse and read
# back through query-api
# When query_range is called with a SATISFIED matcher vs a CONTRADICTING
#      matcher over the same window
# Then the satisfied matcher returns the series and the contradicting
#      matcher returns an empty result — the matcher CHANGES the result.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared; mkdir -p "$SHARED_DATA"
GW_NAME="q06-gw-$$"; QAPI_NAME="q06-qapi-$$"
cleanup() { docker stop --time 5 "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true; docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$GW_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14334:4318 "$GW_IMAGE" > /dev/null
SAW=""; for _ in $(seq 1 30); do docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }; sleep 1; done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14334 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 --otlp-attributes service.name=\"q06-pilot\" \
    > /tmp/tg.out 2> /tmp/tg.err || { echo "telemetrygen failed" >&2; cat /tmp/tg.err >&2; exit 1; }
docker stop --time 10 "$GW_NAME" > /dev/null
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker rm "$GW_NAME" >/dev/null 2>&1 || true

docker run --rm -d --name "$QAPI_NAME" -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19099:9090 "$QAPI_IMAGE" > /dev/null
sleep 3
START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(date -u +%s)
q() { curl -G -sS -o "$2" -w "%{http_code}" \
        --data-urlencode "query=$1" --data-urlencode "start=$START" \
        --data-urlencode "end=$END" --data-urlencode "step=15s" \
        "http://localhost:19099/api/v1/query_range"; }
echo "code_plain=$(q "gen" "'"$EVIDENCE_DIR"'/q06-plain.json")"
echo "code_match=$(q "gen{__name__=\"gen\"}" "'"$EVIDENCE_DIR"'/q06-match.json")"
echo "code_nomatch=$(q "gen{__name__=\"q06zznomatch\"}" "'"$EVIDENCE_DIR"'/q06-nomatch.json")"
docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" Q06 "$INLINE"

len() { jq -r '.data.result | length' "$1" 2>/dev/null; }
PLAIN="$EVIDENCE_DIR/q06-plain.json"; MATCH="$EVIDENCE_DIR/q06-match.json"; NOMATCH="$EVIDENCE_DIR/q06-nomatch.json"

for f in "$PLAIN" "$MATCH" "$NOMATCH"; do
    s=$(jq -r '.status' "$f" 2>/dev/null)
    [[ "$s" == "success" ]] || { echo "FAIL: $(basename "$f") status=$s (expected success)" >&2; cat "$f" >&2; exit 1; }
done
NP=$(len "$PLAIN"); NM=$(len "$MATCH"); NN=$(len "$NOMATCH")
[[ "$NP" -ge 1 ]] || { echo "FAIL: plain gen returned $NP series; ingest/read precondition unmet" >&2; cat "$PLAIN" >&2; exit 1; }
[[ "$NM" -ge 1 ]] || { echo "FAIL: satisfied matcher gen{__name__=\"gen\"} returned $NM series (expected >=1); matcher wrongly dropped the row" >&2; cat "$MATCH" >&2; exit 1; }
[[ "$NN" -eq 0 ]] || { echo "FAIL: contradicting matcher gen{__name__=\"q06zznomatch\"} returned $NN series (expected 0); matcher NOT applied" >&2; cat "$NOMATCH" >&2; exit 1; }

echo "OK — query-api HONOURS label matchers: plain gen = ${NP} series, gen{__name__=\"gen\"} = ${NM} series (satisfied matcher keeps the row), gen{__name__=\"q06zznomatch\"} = ${NN} series (contradicting matcher drops it). The matcher CHANGES the result, unlike Q03 where step is ignored."
