#!/usr/bin/env bash
# CR01 — the consolidated runtime's live metrics loop: a metric ingested into
# the single `kaleidoscope` process is IMMEDIATELY queryable from the same
# process, with NO restart (consolidated-runtime-v0 slice 1, ADR-0076 DD2).
#
# This is the falsifiable differential vs the split deployment (EG01), where the
# gateway must be SIGTERM'd to flush before a separate query-api can read. Here
# one process Arc::clones one Pulse store into both the OTLP ingest sink and the
# metrics query router, so a committed write is visible to a subsequent read in
# the same running process.
#
# Scenario (ONE container, never restarted):
#   1. boot `kaleidoscope` (KALEIDOSCOPE_TENANT=acme); ports 4318 ingest + 9090
#      metrics query.
#   2. query `gen` BEFORE ingest -> 200 success, 0 series (the metric is not
#      pre-present; an empty store answers, proving the query side is live).
#   3. telemetrygen one `gen` metric -> :4318 (OTLP/HTTP).
#   4. query `gen` AFTER ingest, SAME running process -> 200 success, >=1 series.
#   5. assert the container StartedAt is identical before and after -> the
#      process was never restarted; live visibility came from the shared Arc.
#
# Transition-proof: RED if the post-ingest query returns 0 series (no live
# visibility), or if the container restarted between the two queries.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
CRT_NAME="cr01-rt-$$"
cleanup() { docker stop --time 5 "$CRT_NAME" >/dev/null 2>&1 || true; docker rm "$CRT_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$CRT_NAME" -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=info \
    -p 14333:4318 -p 19106:9090 "$CRT_IMAGE" > /dev/null

# readiness: the metrics query port answers a well-formed range query (with
# start/end/step) 200 once the query router is serving. The query routers bind
# quietly (only the ingest aperture listeners emit listener_bound), so we poll
# the HTTP surface, not the log.
RNOW=$(date -u +%s)
RREADY_URL="http://localhost:19106/api/v1/query_range?query=gen&start=$((RNOW-300))&end=${RNOW}&step=15s"
READY=""
for _ in $(seq 1 40); do
    code=$(curl -sS -o /dev/null -w "%{http_code}" "$RREADY_URL" 2>/dev/null || true)
    [[ "$code" == "200" ]] && { READY=yes; break; }
    docker logs "$CRT_NAME" 2>&1 | grep -q "health.startup.refused" && { echo "runtime refused to start" >&2; docker logs "$CRT_NAME" >&2; exit 1; }
    sleep 1
done
[[ "$READY" == "yes" ]] || { echo "runtime never became ready on :9090" >&2; docker logs "$CRT_NAME" >&2 || true; exit 1; }

STARTED_BEFORE=$(docker inspect -f "{{.State.StartedAt}}" "$CRT_NAME")

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); END=$(( $(date -u +%s) + 120 ))
Q="query=gen&start=${START}&end=${END}&step=15s"
qcount() { curl -sS -o "$1" -w "%{http_code}" "http://localhost:19106/api/v1/query_range?${Q}"; }

PRE_CODE=$(qcount "'"$EVIDENCE_DIR"'/pre.json")
echo "pre_code=${PRE_CODE} pre_status=$(jq -r .status "'"$EVIDENCE_DIR"'/pre.json" 2>/dev/null) pre_count=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/pre.json" 2>/dev/null)"

# ingest one `gen` metric into the SAME process via OTLP/HTTP :4318
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14333 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 --otlp-attributes service.name=\"cr01-pilot\" > /tmp/tg.out 2>/tmp/tg.err \
    || { echo "telemetrygen failed" >&2; cat /tmp/tg.err >&2; exit 1; }

# query AFTER ingest, same running process, allow a brief settle (NO restart)
POST_COUNT=0; POST_CODE=000
for _ in $(seq 1 15); do
    POST_CODE=$(qcount "'"$EVIDENCE_DIR"'/post.json")
    POST_COUNT=$(jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/post.json" 2>/dev/null || echo 0)
    [[ "$POST_COUNT" -ge 1 ]] && break
    sleep 1
done
echo "post_code=${POST_CODE} post_status=$(jq -r .status "'"$EVIDENCE_DIR"'/post.json" 2>/dev/null) post_count=${POST_COUNT}"

STARTED_AFTER=$(docker inspect -f "{{.State.StartedAt}}" "$CRT_NAME")
echo "started_before=${STARTED_BEFORE}"
echo "started_after=${STARTED_AFTER}"
docker logs "$CRT_NAME" > "'"$EVIDENCE_DIR"'/runtime.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" CR01 "$INLINE"

OUT="$EVIDENCE_DIR/CR01.stdout.txt"
field() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

[[ "$(field pre_code)" == "200" ]] || fail "pre-ingest query not 200 (got $(field pre_code)); query side not live"
[[ "$(field pre_status)" == "success" ]] || fail "pre-ingest status not success"
[[ "$(field pre_count)" == "0" ]] || fail "pre-ingest returned $(field pre_count) series; the metric was already present (test not isolated)"
[[ "$(field post_code)" == "200" ]] || fail "post-ingest query not 200 (got $(field post_code))"
[[ "$(field post_status)" == "success" ]] || fail "post-ingest status not success"
PC=$(field post_count); [[ "$PC" -ge 1 ]] || fail "POST-INGEST RETURNED $PC SERIES — no live visibility: the metric ingested into the consolidated process was NOT queryable from the same process without a restart (ADR-0076 DD2 falsified)"

SB=$(field started_before); SA=$(field started_after)
[[ -n "$SB" && "$SB" == "$SA" ]] || fail "container StartedAt changed ($SB -> $SA): the process restarted between ingest and query, so live visibility is not proven"

echo "CR01 satisfied — consolidated runtime live metrics loop: gen absent before ingest (0 series), present after ingest (${PC} series) from the SAME process (StartedAt unchanged), no restart. Shared-Arc live visibility holds (ADR-0076 DD2)."
