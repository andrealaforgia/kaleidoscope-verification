#!/usr/bin/env bash
# CR03 — the regression NEGATIVE CONTROL for consolidated-runtime-v0
# (implementer msg 037). It proves the split deployment is NOT live: a metric
# ingested into the SEPARATE kaleidoscope-gateway, AFTER a separate query-api
# has already booted over the same pillar root, is NOT visible to that
# already-running query-api until it is restarted. Paired with CR01/CR02 (the
# consolidated process IS live with no restart), this is the differential that
# proves the consolidation fix is real, not vacuous.
#
# Scenario (same pillar root throughout):
#   1. boot query-api over a fresh empty root (KALEIDOSCOPE_QUERY_TENANT=acme),
#      leave it RUNNING. query gen -> 0 (empty, as expected).
#   2. boot the gateway over the SAME root, telemetrygen one `gen`, SIGTERM the
#      gateway to flush Pulse to disk (so the record is durably on disk).
#   3. query the STILL-RUNNING query-api -> EXPECT 0 series: it loaded the store
#      at boot and does not see the post-boot write (the regression).
#   4. start a FRESH query-api over the same root (a "restart") and query ->
#      EXPECT >=1 series: the record IS on disk, visible only after a reload.
#
# Expected GREEN posture: running=0 (not live), restarted>=1 (durable, needs
# restart). If the already-running query-api returns >=1 at step 3, the
# regression does NOT reproduce (the split path is live too) -- that is itself a
# reportable finding (the consolidation differential would be weaker than the
# feature claims), and this expectation goes RED naming it.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED=$DATA_HOST/shared; mkdir -p "$SHARED"
GW="cr03-gw-$$"; QRUN="cr03-qrun-$$"; QNEW="cr03-qnew-$$"
cleanup() { docker stop --time 5 "$GW" "$QRUN" "$QNEW" >/dev/null 2>&1 || true; docker rm "$GW" "$QRUN" "$QNEW" >/dev/null 2>&1 || true; }
trap cleanup EXIT

S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
qurl() { echo "http://localhost:$1/api/v1/query_range?query=gen&start=${S}&end=${E}&step=15s"; }

# 1. query-api running over a fresh empty root.
docker run --rm -d --name "$QRUN" -v "$SHARED:/data" -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info -p 19115:9090 "$QAPI_IMAGE" > /dev/null
for _ in $(seq 1 30); do [[ "$(curl -sS -o /dev/null -w "%{http_code}" "$(qurl 19115)" 2>/dev/null)" == "200" ]] && break; sleep 1; done
echo "running_empty=$(curl -sS -o "'"$EVIDENCE_DIR"'/run_empty.json" "$(qurl 19115)"; jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/run_empty.json" 2>/dev/null)"

# 2. gateway ingests into the SAME root, then SIGTERM to flush to disk.
docker run --rm -d --name "$GW" -v "$SHARED:/data" -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14335:4318 "$GW_IMAGE" > /dev/null
for _ in $(seq 1 30); do docker logs "$GW" 2>&1 | grep -q "gateway_starting\|listener_bound" && break; sleep 1; done
sleep 2
docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    metrics --otlp-endpoint localhost:14335 --otlp-insecure --otlp-http --duration 1s --rate 1 --otlp-attributes service.name=\"cr03-pilot\" >/dev/null 2>&1
docker stop --time 10 "$GW" >/dev/null   # SIGTERM flush
docker rm "$GW" >/dev/null 2>&1 || true

# 3. query the STILL-RUNNING query-api -> expect 0 (not live).
sleep 2
echo "running_after_ingest=$(curl -sS -o "'"$EVIDENCE_DIR"'/run_after.json" "$(qurl 19115)"; jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/run_after.json" 2>/dev/null)"
docker stop --time 5 "$QRUN" >/dev/null 2>&1 || true; docker rm "$QRUN" >/dev/null 2>&1 || true

# 4. fresh query-api over the same root (restart) -> expect >=1 (durable).
docker run --rm -d --name "$QNEW" -v "$SHARED:/data" -e KALEIDOSCOPE_QUERY_TENANT=acme -e RUST_LOG=info -p 19116:9090 "$QAPI_IMAGE" > /dev/null
RC=0
for _ in $(seq 1 30); do
    [[ "$(curl -sS -o /dev/null -w "%{http_code}" "$(qurl 19116)" 2>/dev/null)" == "200" ]] || { sleep 1; continue; }
    RC=$(curl -sS -o "'"$EVIDENCE_DIR"'/restart.json" "$(qurl 19116)"; jq -r ".data.result|length" "'"$EVIDENCE_DIR"'/restart.json" 2>/dev/null)
    [[ "$RC" =~ ^[0-9]+$ && "$RC" -ge 1 ]] && break; sleep 1
done
echo "restarted=${RC}"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" CR03 "$INLINE"

OUT="$EVIDENCE_DIR/CR03.stdout.txt"
f() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

[[ "$(f running_empty)" == "0" ]] || fail "query-api was not empty at boot ($(f running_empty)); test not isolated"
RUN_AFTER=$(f running_after_ingest)
[[ "$RUN_AFTER" == "0" ]] || fail "REGRESSION DID NOT REPRODUCE: the already-running split query-api returned $RUN_AFTER series for a post-boot ingest — the split path IS live without restart, so the consolidation differential is weaker than consolidated-runtime-v0 claims (reportable)"
RESTART=$(f restarted)
[[ "$RESTART" =~ ^[0-9]+$ && "$RESTART" -ge 1 ]] || fail "after a restart the data was still not visible ($RESTART series) — the ingest never reached disk, so the negative control is inconclusive (not the clean regression)"
echo "CR03 satisfied — split path is NOT live: a post-boot ingest is invisible to the already-running query-api (0 series) and only appears after a restart (${RESTART} series). This is the regression the consolidated runtime fixes; with CR01/CR02 (live, no restart) the differential is proven real."
