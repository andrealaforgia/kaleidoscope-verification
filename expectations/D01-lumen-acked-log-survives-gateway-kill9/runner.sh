#!/usr/bin/env bash
# D01 — durability: a log record acked by the gateway survives a HARD
# kill (SIGKILL / kill -9) of the gateway, with NO graceful shutdown,
# and is recovered on the next open of the Lumen store.
#
# This is distinct from LQ02 (which used SIGTERM, i.e. the graceful
# Drop-flush path). D01 proves the WAL-flush-BEFORE-ack contract:
# lumen::FileBackedLogStore::ingest appends the record to the WAL and
# `flush()`es it (hands it to the kernel via write(2)) BEFORE returning
# the receipt the gateway acks on (crates/lumen/src/file_backed.rs
# append_wal). So a kill -9 of the gateway process cannot lose an acked
# record — the bytes are already in the OS page cache — and
# FileBackedLogStore::open replays the WAL on restart. (fsync, which
# additionally protects against OS crash / power loss, is a stronger
# guarantee not exercised here; this is process-kill durability.)
#
# Scenario:
#   1. gateway up, writable /data, tenant acme.
#   2. telemetrygen logs --body d01-survivor; telemetrygen exiting 0
#      proves the gateway ACKED (the OTLP response came back), which
#      means ingest() returned, which means the WAL was flushed.
#   3. `docker kill --signal=KILL` the gateway — a hard kill, NO
#      SIGTERM, so the graceful Drop-flush never runs.
#   4. start log-query-api on the SAME /data (it opens the store and
#      replays the WAL) and query body_contains=d01-survivor.
#   5. the acked record is present.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NEEDLE="d01-survivor-marker"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="d01-gw-$$"
LQ_NAME="d01-lqapi-$$"

cleanup() {
    docker kill "$GW_NAME" >/dev/null 2>&1 || true
    docker stop --time 5 "$LQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# No --rm on the gateway: we hard-kill it and then inspect its exit
# code (137 == SIGKILL), which a --rm container would auto-remove
# before we could read. The trap and an explicit rm clean it up.
docker run -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14324:4318 \
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

# Emit logs; telemetrygen exit 0 == the gateway acked (WAL flushed).
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    logs \
    --otlp-endpoint localhost:14324 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 \
    --body "$NEEDLE" \
    --otlp-attributes service.name=\"d01-pilot\" \
    > /tmp/tgd.out 2> /tmp/tgd.err
TG_EC=$?
cp /tmp/tgd.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"
echo "telemetrygen_exit=$TG_EC"
[[ "$TG_EC" == "0" ]] || { echo "telemetrygen did not get an ack (exit $TG_EC); cannot claim acked-durability" >&2; cat /tmp/tgd.err >&2; exit 1; }
# Brief settle so the ingest definitely completed before the hard kill.
sleep 1

# HARD KILL: SIGKILL to the gateway. NO graceful shutdown / Drop flush.
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker kill --signal=KILL "$GW_NAME" > /dev/null
# Record the exit code: 137 == 128 + 9 (SIGKILL), proving a hard kill.
GW_EXIT=$(docker inspect -f "{{.State.ExitCode}}" "$GW_NAME" 2>/dev/null || echo "gone")
echo "gateway_kill_exit=$GW_EXIT"
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# Reopen the SAME store via log-query-api; it replays the WAL.
docker run --rm -d \
    --name "$LQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19099:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
curl -sS -G -o "'"$EVIDENCE_DIR"'/d01-after-kill.json" -w "query_code=%{http_code}\n" \
    "http://localhost:19099/api/v1/logs" \
    --data-urlencode "start=${START}" --data-urlencode "end=${END}" \
    --data-urlencode "body_contains=${NEEDLE}"
docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true
echo "survivors=$(jq length "'"$EVIDENCE_DIR"'/d01-after-kill.json")"
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" D01 "$INLINE"

OUT="$EVIDENCE_DIR/D01.stdout.txt"
NEEDLE="d01-survivor-marker"   # must match the INLINE marker
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }

[[ "$(val telemetrygen_exit)" == "0" ]] || { echo "no ack; precondition failed" >&2; exit 1; }
KEC=$(val gateway_kill_exit)
[[ "$KEC" == "137" ]] || { echo "gateway exit was '$KEC', expected 137 (128+SIGKILL); the kill was not a hard kill" >&2; exit 1; }
[[ "$(val query_code)" == "200" ]] || { echo "post-kill query expected 200, got $(val query_code)" >&2; exit 1; }

AFTER="$EVIDENCE_DIR/d01-after-kill.json"
SURV=$(jq 'length' "$AFTER")
[[ "$SURV" -ge 1 ]] || { echo "DURABILITY FAILURE: 0 acked records survived the gateway SIGKILL" >&2; cat "$AFTER" >&2; exit 1; }
NON_MATCH=$(jq --arg n "$NEEDLE" '[.[] | select((.body|contains($n))|not)] | length' "$AFTER")
[[ "$NON_MATCH" == "0" ]] || { echo "post-kill result has $NON_MATCH records lacking the needle" >&2; exit 1; }

echo "OK — durability: an acked log survives a gateway SIGKILL (exit 137, no graceful flush); ${SURV} record(s) recovered from the Lumen WAL on reopen, all carrying the needle"
