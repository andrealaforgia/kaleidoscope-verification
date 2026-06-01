#!/usr/bin/env bash
# D03 — durability (Ray pillar): a span acked by the gateway survives a
# HARD kill (SIGKILL) of the gateway and is recovered on the next open
# of the Ray store, readable via trace-query-api's window arm.
#
# Ray's contract matches Lumen's (NOT Pulse's): its append_wal does
# `write_all` + `flush()` (hands the bytes to the kernel via write(2))
# BEFORE `ingest` returns the receipt the gateway acks on
# (crates/ray/src/file_backed.rs:393), but does NOT fsync. So this is
# PROCESS-kill durability (the OS page cache survives the dead process),
# NOT OS-crash / power-loss durability.
#
# Scenario mirrors D01/D02 on the traces path:
#   1. gateway up, writable /data, tenant acme.
#   2. telemetrygen traces (service d03-pilot); exit 0 proves the ack.
#   3. `docker kill --signal=KILL` the gateway (exit 137, no flush).
#   4. trace-query-api on the SAME /data replays the Ray WAL; query the
#      window arm by service.
#   5. the acked spans are present, all carrying d03-pilot.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SERVICE="d03-pilot"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="d03-gw-$$"
TQ_NAME="d03-tqapi-$$"

cleanup() {
    docker kill "$GW_NAME" >/dev/null 2>&1 || true
    docker stop --time 5 "$TQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$TQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# No --rm on the gateway so its post-kill exit code is inspectable.
docker run -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14326:4318 \
    "$GW_IMAGE" > /dev/null
SAW=""
for i in $(seq 1 30); do
    if docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound"; then
        SAW="yes"; break
    fi
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never emitted gateway_starting" >&2; exit 1; }
sleep 2

docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    traces \
    --otlp-endpoint localhost:14326 --otlp-insecure --otlp-http \
    --traces 5 --child-spans 1 \
    --service "$SERVICE" \
    > /tmp/tgt.out 2> /tmp/tgt.err
TG_EC=$?
cp /tmp/tgt.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"
echo "telemetrygen_exit=$TG_EC"
[[ "$TG_EC" == "0" ]] || { echo "telemetrygen did not get an ack (exit $TG_EC)" >&2; cat /tmp/tgt.err >&2; exit 1; }
sleep 1

# HARD KILL.
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker kill --signal=KILL "$GW_NAME" > /dev/null
GW_EXIT=$(docker inspect -f "{{.State.ExitCode}}" "$GW_NAME" 2>/dev/null || echo "gone")
echo "gateway_kill_exit=$GW_EXIT"
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# Reopen the Ray store via trace-query-api (WAL replay on open).
docker run -d \
    --name "$TQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_TRACE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19101:9092 \
    "$TQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
curl -sS -G -o "'"$EVIDENCE_DIR"'/d03-after-kill.json" -w "query_code=%{http_code}\n" \
    "http://localhost:19101/api/v1/traces" \
    --data-urlencode "service=${SERVICE}" --data-urlencode "start=${START}" --data-urlencode "end=${END}"
docker logs "$TQ_NAME" > "'"$EVIDENCE_DIR"'/trace-query-api.stderr.txt" 2>&1 || true
echo "survivors=$(jq length "'"$EVIDENCE_DIR"'/d03-after-kill.json")"
docker stop --time 5 "$TQ_NAME" >/dev/null 2>&1 || true
docker rm "$TQ_NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" D03 "$INLINE"

OUT="$EVIDENCE_DIR/D03.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
AFTER="$EVIDENCE_DIR/d03-after-kill.json"

[[ "$(val telemetrygen_exit)" == "0" ]] || { echo "no ack; precondition failed" >&2; exit 1; }
[[ "$(val gateway_kill_exit)" == "137" ]] || { echo "gateway exit was '$(val gateway_kill_exit)', expected 137 (SIGKILL)" >&2; exit 1; }
[[ "$(val query_code)" == "200" ]] || { echo "post-kill query expected 200, got $(val query_code)" >&2; exit 1; }

SURV=$(jq 'length' "$AFTER")
[[ "$SURV" -ge 1 ]] || { echo "DURABILITY FAILURE: 0 acked spans survived the gateway SIGKILL" >&2; cat "$AFTER" >&2; exit 1; }
WRONG=$(jq --arg s "d03-pilot" '[.[] | select((.resource_attributes."service.name") != $s)] | length' "$AFTER")
[[ "$WRONG" == "0" ]] || { echo "post-kill result has $WRONG spans with the wrong service" >&2; cat "$AFTER" >&2; exit 1; }

echo "OK — durability (Ray): acked spans survive a gateway SIGKILL (exit 137, no graceful flush); ${SURV} span(s) recovered from the Ray WAL on reopen, all carrying service=d03-pilot"
