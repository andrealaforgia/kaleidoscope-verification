#!/usr/bin/env bash
# CR02 — the three-signal live loop on ONE consolidated process, plus the
# continuous-live-state sharpening (consolidated-runtime-v0 slice 2 `2a74e4f`,
# ADR-0076; closes C1). metrics, logs AND traces ingested into the single
# `kaleidoscope` process are each immediately queryable from their own query
# router, no restart, all over shared Arc stores (pulse/lumen/ray).
#
# Scenario, ONE container, never restarted:
#   metrics (the sharp double-ingest, per implementer msg 037):
#     - query `gen` before ingest -> 0 series
#     - telemetrygen metrics svc=cr02svc1 -> query -> >=1 series
#     - telemetrygen metrics svc=cr02svc2 (a SECOND, post-query ingest)
#       -> query -> STRICTLY MORE series than after the first
#       (continuous shared live state, not a one-time startup load)
#   logs:
#     - query body_contains=<needle> before ingest -> 0 records
#     - telemetrygen logs --body <needle> -> query -> >=1 record
#   traces:
#     - query service=<svc> before ingest -> 0 spans
#     - telemetrygen traces --service <svc> -> query -> >=1 span
#   then assert the container StartedAt is unchanged across the whole loop.
#
# Transition-proof: RED if any signal is not live (post-ingest empty), if the
# second metric ingest is not visible without restart, or if the process
# restarted.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
CRT_NAME="cr02-rt-$$"
cleanup() { docker stop --time 5 "$CRT_NAME" >/dev/null 2>&1 || true; docker rm "$CRT_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run --rm -d --name "$CRT_NAME" -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_TENANT=acme -e KALEIDOSCOPE_DEMO_OVERLAY=0 -e RUST_LOG=info \
    -p 14334:4318 -p 19110:9090 -p 19111:9091 -p 19112:9092 "$CRT_IMAGE" > /dev/null

RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    code=$(curl -sS -o /dev/null -w "%{http_code}" "http://localhost:19110/api/v1/query_range?query=gen&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null || true)
    [[ "$code" == "200" ]] && { READY=yes; break; }
    docker logs "$CRT_NAME" 2>&1 | grep -q "health.startup.refused" && { echo "runtime refused" >&2; docker logs "$CRT_NAME" >&2; exit 1; }
    sleep 1
done
[[ "${READY:-}" == "yes" ]] || { echo "runtime never ready" >&2; docker logs "$CRT_NAME" >&2 || true; exit 1; }

STARTED_BEFORE=$(docker inspect -f "{{.State.StartedAt}}" "$CRT_NAME")
S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
NEEDLE="cr02-needle-ziggurat"; SVC="cr02-trace-svc"

mq() { curl -sS -o "$1" "http://localhost:19110/api/v1/query_range?query=gen&start=${S}&end=${E}&step=15s"; jq -r ".data.result|length" "$1" 2>/dev/null || echo NA; }
lq() { curl -sS -o "$1" "http://localhost:19111/api/v1/logs?start=${S}&end=${E}&body_contains=${NEEDLE}"; jq -r "if type==\"array\" then length else 0 end" "$1" 2>/dev/null || echo NA; }
tq() { curl -sS -G -o "$1" "http://localhost:19112/api/v1/traces" --data-urlencode "service=${SVC}" --data-urlencode "start=${S}" --data-urlencode "end=${E}"; jq -r "if type==\"array\" then length else 0 end" "$1" 2>/dev/null || echo NA; }
tgen() { docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 "$@" >/dev/null 2>&1; }

echo "m_pre=$(mq "'"$EVIDENCE_DIR"'/m_pre.json")"
tgen metrics --otlp-endpoint localhost:14334 --otlp-insecure --otlp-http --duration 1s --rate 1 --otlp-attributes service.name=\"cr02svc1\"
M1=0; for _ in $(seq 1 15); do M1=$(mq "'"$EVIDENCE_DIR"'/m1.json"); [[ "$M1" =~ ^[0-9]+$ && "$M1" -ge 1 ]] && break; sleep 1; done; echo "m_after1=${M1}"
tgen metrics --otlp-endpoint localhost:14334 --otlp-insecure --otlp-http --duration 1s --rate 1 --otlp-attributes service.name=\"cr02svc2\"
M2=0; for _ in $(seq 1 15); do M2=$(mq "'"$EVIDENCE_DIR"'/m2.json"); [[ "$M2" =~ ^[0-9]+$ && "$M2" -gt "$M1" ]] && break; sleep 1; done; echo "m_after2=${M2}"

echo "l_pre=$(lq "'"$EVIDENCE_DIR"'/l_pre.json")"
tgen logs --otlp-endpoint localhost:14334 --otlp-insecure --otlp-http --duration 1s --rate 5 --body "$NEEDLE" --otlp-attributes service.name=\"cr02-log\"
L1=0; for _ in $(seq 1 15); do L1=$(lq "'"$EVIDENCE_DIR"'/l1.json"); [[ "$L1" =~ ^[0-9]+$ && "$L1" -ge 1 ]] && break; sleep 1; done; echo "l_after=${L1}"

echo "t_pre=$(tq "'"$EVIDENCE_DIR"'/t_pre.json")"
tgen traces --otlp-endpoint localhost:14334 --otlp-insecure --otlp-http --traces 5 --child-spans 1 --service "$SVC"
T1=0; for _ in $(seq 1 15); do T1=$(tq "'"$EVIDENCE_DIR"'/t1.json"); [[ "$T1" =~ ^[0-9]+$ && "$T1" -ge 1 ]] && break; sleep 1; done; echo "t_after=${T1}"

STARTED_AFTER=$(docker inspect -f "{{.State.StartedAt}}" "$CRT_NAME")
echo "started_before=${STARTED_BEFORE}"
echo "started_after=${STARTED_AFTER}"
docker logs "$CRT_NAME" > "'"$EVIDENCE_DIR"'/runtime.stderr.txt" 2>&1 || true
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" CR02 "$INLINE"

OUT="$EVIDENCE_DIR/CR02.stdout.txt"
f() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

[[ "$(f m_pre)" == "0" ]] || fail "metrics present before ingest ($(f m_pre)); not isolated"
[[ "$(f m_after1)" -ge 1 ]] 2>/dev/null || fail "metric not live after first ingest ($(f m_after1) series)"
[[ "$(f m_after2)" -gt "$(f m_after1)" ]] 2>/dev/null || fail "SECOND metric ingest not visible without restart (after1=$(f m_after1), after2=$(f m_after2)) — continuous shared live state falsified (one-time startup load only)"
echo "OK metrics: 0 before, $(f m_after1) after first, $(f m_after2) after second (continuous live state, no restart)"

[[ "$(f l_pre)" == "0" ]] || fail "logs present before ingest ($(f l_pre)); not isolated"
[[ "$(f l_after)" -ge 1 ]] 2>/dev/null || fail "logs not live after ingest ($(f l_after) records)"
echo "OK logs: 0 before, $(f l_after) after (live on :9091)"

[[ "$(f t_pre)" == "0" ]] || fail "traces present before ingest ($(f t_pre)); not isolated"
[[ "$(f t_after)" -ge 1 ]] 2>/dev/null || fail "traces not live after ingest ($(f t_after) spans)"
echo "OK traces: 0 before, $(f t_after) after (live on :9092)"

SB=$(f started_before); SA=$(f started_after)
[[ -n "$SB" && "$SB" == "$SA" ]] || fail "container restarted ($SB -> $SA); live visibility not proven"

echo "CR02 satisfied — all three signals live in one process: metrics (continuous, two ingests visible no restart), logs and traces each empty-before / present-after, StartedAt unchanged (no restart). Shared lumen/ray/pulse Arc live visibility holds (ADR-0076)."
