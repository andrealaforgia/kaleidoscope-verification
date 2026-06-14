#!/usr/bin/env bash
# CRGEN-02 — the generator FAILS CLOSED on an unreachable ingest endpoint
# (the implementer asked me to attack this hardest). A mandatory pre-flight
# reachability probe runs BEFORE any emit; against a dead endpoint the generator
# exits NON-ZERO, NAMES the unreachable endpoint on stderr, and emits ZERO
# bytes — never a silent success into the void.
#
# Scenario: a live runtime is up (so "emitted nothing" is checkable against its
# stores), but the generator is pointed at a CLOSED port on it (:4399, not a
# listener). The probe must fail and the generator must refuse.
#
# Asserts: generator exit != 0; stderr names the endpoint + an unreachable/
# bring-the-stack-up reason; and the runtime's three stores stay EMPTY (nothing
# leaked past the probe).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
docker build -q -t kx-runtime:crgen -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:crgen -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="crgen2-net-$$"; RT="crgen2-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19290:9090 -p 19291:9091 -p 19292:9092 kx-runtime:crgen > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19290/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

# generator pointed at a CLOSED port (:4399) on the live runtime host.
DEAD="http://$RT:4399"
GEN_EXIT=0
docker run --rm --network "$NET" \
    -e OTEL_EXPORTER_OTLP_ENDPOINT="$DEAD" -e KALEIDOSCOPE_TENANT=acme \
    kx-gen:crgen > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" || GEN_EXIT=$?
echo "gen_exit=${GEN_EXIT}"

# after the failed probe, the stores must be empty (nothing emitted).
sleep 2
S=$((RNOW-300)); E=$(( $(date -u +%s) + 120 ))
MS=$(curl -s "http://localhost:19290/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo NA)
LH=$(curl -s "http://localhost:19291/api/v1/logs?start=${S}&end=${E}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else 0)' 2>/dev/null || echo NA)
SC=$(curl -s "http://localhost:19292/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}" | python3 -c 'import sys,json;s=json.load(sys.stdin);print(len(s) if isinstance(s,list) else 0)' 2>/dev/null || echo NA)
echo "metrics_after=${MS} logs_after=${LH} spans_after=${SC}"
cp "$EVIDENCE_DIR/gen.err" "$EVIDENCE_DIR/gen.err.txt"

fail() { echo "FAIL: $1" >&2; echo "--- gen.err ---" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
[ "$GEN_EXIT" != "0" ] || fail "generator exited 0 against a DEAD endpoint — it did NOT fail closed (silent success into the void)"
grep -qE '4399' "$EVIDENCE_DIR/gen.err" || fail "stderr does not NAME the unreachable endpoint (:4399)"
grep -qiE 'unreachable|could not|refused|bring the stack up|make up|connect' "$EVIDENCE_DIR/gen.err" || fail "stderr does not give a clear unreachable reason"
[ "$MS" = "0" ] || fail "metrics store not empty after the failed probe ($MS series) — bytes leaked past the reachability gate"
[ "$LH" = "0" ] || fail "logs store not empty after the failed probe ($LH records) — bytes leaked"
[ "$SC" = "0" ] || fail "trace store not empty after the failed probe ($SC spans) — bytes leaked"

echo "CRGEN02 satisfied — generator fails closed on an unreachable endpoint: exit ${GEN_EXIT} (non-zero), endpoint :4399 named on stderr with an unreachable reason, and zero bytes emitted (all three runtime stores empty). Probe-before-emit holds."
