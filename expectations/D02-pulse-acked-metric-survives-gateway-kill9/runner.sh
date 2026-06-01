#!/usr/bin/env bash
# D02 — durability (Pulse pillar): a metric acked by the gateway
# survives a HARD kill (SIGKILL) of the gateway and is recovered on the
# next open of the Pulse store, readable via query-api.
#
# Pulse's guarantee is STRONGER than Lumen's (D01): its append_wal does
# `flush()` THEN `fsync_backend.fsync_file()` (sync_all) per record
# BEFORE `ingest` returns the receipt the gateway acks on
# (crates/pulse/src/file_backed.rs, ADR-0049 §4). So an acked metric is
# durable on stable storage, not merely in the OS page cache. This
# expectation still only DEMONSTRATES process-kill survival (the harness
# cannot power-cycle the disk), but the underlying mechanism is
# fsync-before-ack, so even an OS crash would not lose it.
#
# Scenario mirrors D01 on the metrics path:
#   1. gateway up, writable /data, tenant acme.
#   2. telemetrygen metrics (counter `gen`, service d02-pilot); exit 0
#      proves the gateway ACKED (and therefore fsync'd).
#   3. `docker kill --signal=KILL` the gateway (exit 137, no flush).
#   4. query-api on the SAME /data replays the Pulse WAL; query `gen`.
#   5. the acked series is present (status=success, __name__=gen).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="d02-gw-$$"
QAPI_NAME="d02-qapi-$$"

cleanup() {
    docker kill "$GW_NAME" >/dev/null 2>&1 || true
    docker stop --time 5 "$QAPI_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$QAPI_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# No --rm on the gateway so its post-kill exit code is inspectable.
docker run -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme \
    -e RUST_LOG=info \
    -p 14325:4318 \
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
    metrics \
    --otlp-endpoint localhost:14325 --otlp-insecure --otlp-http \
    --duration 1s --rate 1 \
    --otlp-attributes service.name=\"d02-pilot\" \
    > /tmp/tgm.out 2> /tmp/tgm.err
TG_EC=$?
cp /tmp/tgm.err "'"$EVIDENCE_DIR"'/telemetrygen.stderr.txt"
echo "telemetrygen_exit=$TG_EC"
[[ "$TG_EC" == "0" ]] || { echo "telemetrygen did not get an ack (exit $TG_EC)" >&2; cat /tmp/tgm.err >&2; exit 1; }
sleep 1

# HARD KILL.
docker logs "$GW_NAME" > "'"$EVIDENCE_DIR"'/gateway.stderr.txt" 2>&1 || true
docker kill --signal=KILL "$GW_NAME" > /dev/null
GW_EXIT=$(docker inspect -f "{{.State.ExitCode}}" "$GW_NAME" 2>/dev/null || echo "gone")
echo "gateway_kill_exit=$GW_EXIT"
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# Reopen the Pulse store via query-api (WAL replay on open).
docker run -d \
    --name "$QAPI_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_QUERY_TENANT=acme \
    -e RUST_LOG=info \
    -p 19100:9090 \
    "$QAPI_IMAGE" > /dev/null
sleep 3

START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
END=$(( $(date -u +%s) + 120 ))
curl -sS -o "'"$EVIDENCE_DIR"'/d02-after-kill.json" -w "query_code=%{http_code}\n" \
    "http://localhost:19100/api/v1/query_range?query=gen&start=${START}&end=${END}&step=15s"
docker logs "$QAPI_NAME" > "'"$EVIDENCE_DIR"'/query-api.stderr.txt" 2>&1 || true
echo "---response head---"; head -c 300 "'"$EVIDENCE_DIR"'/d02-after-kill.json"; echo
docker stop --time 5 "$QAPI_NAME" >/dev/null 2>&1 || true
docker rm "$QAPI_NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" D02 "$INLINE"

OUT="$EVIDENCE_DIR/D02.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
AFTER="$EVIDENCE_DIR/d02-after-kill.json"

[[ "$(val telemetrygen_exit)" == "0" ]] || { echo "no ack; precondition failed" >&2; exit 1; }
[[ "$(val gateway_kill_exit)" == "137" ]] || { echo "gateway exit was '$(val gateway_kill_exit)', expected 137 (SIGKILL)" >&2; exit 1; }
[[ "$(val query_code)" == "200" ]] || { echo "post-kill query expected 200, got $(val query_code)" >&2; exit 1; }

STATUS=$(jq -r '.status' "$AFTER")
[[ "$STATUS" == "success" ]] || { echo "DURABILITY FAILURE: post-kill query status=$STATUS" >&2; cat "$AFTER" >&2; exit 1; }
RESULT_COUNT=$(jq -r '.data.result | length' "$AFTER")
[[ "$RESULT_COUNT" -ge 1 ]] || { echo "DURABILITY FAILURE: 0 series survived the gateway SIGKILL" >&2; cat "$AFTER" >&2; exit 1; }
NAME=$(jq -r '.data.result[0].metric.__name__' "$AFTER")
[[ "$NAME" == "gen" ]] || { echo "recovered series has __name__=$NAME, expected gen" >&2; exit 1; }

echo "OK — durability (Pulse): an acked metric survives a gateway SIGKILL (exit 137, no graceful flush); recovered from the fsync'd Pulse WAL on reopen (status=success, __name__=gen)"
