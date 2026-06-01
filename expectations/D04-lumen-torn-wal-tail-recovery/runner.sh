#!/usr/bin/env bash
# D04 — OBSERVATION (capture-first): how does Lumen recovery behave when
# the WAL's trailing line is TORN (incomplete JSON, no newline) — the
# exact shape a real mid-write crash / power loss leaves behind?
#
# This is the deterministic complement to D01-D03 (which kill AFTER the
# ack). Instead of racing a kill into the tiny write_all+flush window,
# we deterministically corrupt the WAL tail on disk and observe the
# read service's behaviour on reopen. The observable: does log-query-api
# (a) start and serve the intact prior records, ignoring the torn tail,
# or (b) refuse to open at all (fail-closed), or (c) crash / serve
# corrupt data?
#
# The runner captures everything and asserts only the SAFE invariant:
# the service must NOT serve corrupt or partial data — it either
# recovers the intact records cleanly OR fails closed with a clear
# error. Silently serving a torn record would be the real bug.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NEEDLE="d04-survivor-marker"
SHARED_DATA=$DATA_HOST/shared
mkdir -p "$SHARED_DATA"
GW_NAME="d04-gw-$$"
LQ_NAME="d04-lqapi-$$"

cleanup() {
    docker stop --time 5 "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
    docker rm "$GW_NAME" "$LQ_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Ingest a few logs and stop the gateway CLEANLY (SIGTERM) so the
#    WAL holds only well-formed lines to begin with.
docker run --rm -d \
    --name "$GW_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info \
    -p 14327:4318 \
    "$GW_IMAGE" > /dev/null
SAW=""
for i in $(seq 1 30); do
    docker logs "$GW_NAME" 2>&1 | grep -q "gateway_starting\|listener_bound" && { SAW=yes; break; }
    sleep 1
done
[[ "$SAW" == "yes" ]] || { echo "gateway never started" >&2; exit 1; }
sleep 2
docker run --rm --network host \
    ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 \
    logs --otlp-endpoint localhost:14327 --otlp-insecure --otlp-http \
    --duration 1s --rate 5 --body "$NEEDLE" \
    --otlp-attributes service.name=\"d04-pilot\" > /dev/null 2>&1
docker stop --time 10 "$GW_NAME" >/dev/null
docker rm "$GW_NAME" >/dev/null 2>&1 || true

# 2. Capture the intact WAL, then TEAR the tail: append an incomplete
#    JSON line with no trailing newline (a half-written record).
WAL="$SHARED_DATA/lumen.wal"
ls -l "$SHARED_DATA" > "'"$EVIDENCE_DIR"'/data-listing.txt" 2>&1 || true
if [[ -f "$WAL" ]]; then
    cp "$WAL" "'"$EVIDENCE_DIR"'/lumen.wal.before"
    LINES_BEFORE=$(wc -l < "$WAL" | tr -d " ")
    printf "%s" "{\"op\":\"ingest\",\"tenant\":\"acme\",\"records\":[{\"observed_time_unix_nano\":17800000000000000" >> "$WAL"
    cp "$WAL" "'"$EVIDENCE_DIR"'/lumen.wal.after"
else
    echo "WAL_NOT_FOUND_at_$WAL"
    LINES_BEFORE=NA
fi
echo "wal_lines_before_tear=$LINES_BEFORE"

# 3. Start log-query-api on the torn /data; observe open behaviour.
LQ_EC=0
docker run -d \
    --name "$LQ_NAME" \
    -v "$SHARED_DATA:/data" \
    -e KALEIDOSCOPE_LOG_QUERY_TENANT=acme -e RUST_LOG=info \
    -p 19102:9091 \
    "$LQAPI_IMAGE" > /dev/null
sleep 4
RUNNING=$(docker inspect -f "{{.State.Running}}" "$LQ_NAME" 2>/dev/null || echo "gone")
EXITCODE=$(docker inspect -f "{{.State.ExitCode}}" "$LQ_NAME" 2>/dev/null || echo "gone")
echo "lqapi_running=$RUNNING lqapi_exitcode=$EXITCODE"
docker logs "$LQ_NAME" > "'"$EVIDENCE_DIR"'/log-query-api.stderr.txt" 2>&1 || true

# 4. If it is up, query; capture code + body (may be connection-refused).
QCODE=000
if [[ "$RUNNING" == "true" ]]; then
    START=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s)
    END=$(( $(date -u +%s) + 120 ))
    QCODE=$(curl -sS -G -o "'"$EVIDENCE_DIR"'/d04-query.json" -w "%{http_code}" \
        "http://localhost:19102/api/v1/logs" \
        --data-urlencode "start=${START}" --data-urlencode "end=${END}" \
        --data-urlencode "body_contains=${NEEDLE}" 2>/dev/null || echo "000")
fi
echo "query_code=$QCODE"
[[ -f "'"$EVIDENCE_DIR"'/d04-query.json" ]] && echo "query_count=$(jq length "'"$EVIDENCE_DIR"'/d04-query.json" 2>/dev/null || echo NA)"
docker stop --time 3 "$LQ_NAME" >/dev/null 2>&1 || true
docker rm "$LQ_NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-eg.sh" "$EVIDENCE_DIR" D04 "$INLINE"

OUT="$EVIDENCE_DIR/D04.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
RUNNING=$(val lqapi_running)
EXITCODE=$(val lqapi_exitcode)
QCODE=$(val query_code)

# SAFE INVARIANT: the read service must NOT serve corrupt or partial
# data off a torn WAL. Two acceptable shapes:
#   (A) it recovers the intact records and ignores the torn tail
#       (running=true, query 200, every returned body carries the
#        needle, no half-record), or
#   (B) it FAILS CLOSED on the torn WAL with a clear error (does not
#       bind / exits non-zero, no data served).
# Anything else (crash with no clear error, or serving a torn record)
# is a failure.
if [[ "$RUNNING" == "true" ]]; then
    [[ "$QCODE" == "200" ]] || { echo "service is up but query returned $QCODE" >&2; exit 1; }
    BAD=$(jq --arg n "d04-survivor-marker" '[.[] | select((.body|contains($n))|not)] | length' "$EVIDENCE_DIR/d04-query.json")
    [[ "$BAD" == "0" ]] || { echo "served $BAD records NOT carrying the needle (possible torn/corrupt record)" >&2; exit 1; }
    echo "OK — torn WAL tail tolerated: log-query-api recovered the intact records and ignored the torn trailing line (graceful recovery)"
else
    # Fail-closed branch: must be a clean non-zero exit with a clear
    # PersistenceFailed WAL-parse error, NOT a silent crash.
    [[ "$EXITCODE" != "0" && "$EXITCODE" != "gone" ]] || { echo "service is not running but exit code is '$EXITCODE'" >&2; exit 1; }
    grep -qE 'PersistenceFailed.*WAL parse error' "$EVIDENCE_DIR/log-query-api.stderr.txt" \
        || { echo "fail-closed but without a clear PersistenceFailed WAL-parse error on stderr" >&2; cat "$EVIDENCE_DIR/log-query-api.stderr.txt" >&2; exit 1; }
    echo "OK — torn WAL tail does NOT yield corrupt data: log-query-api fails closed (exit ${EXITCODE}) with a clear 'PersistenceFailed: WAL parse error' and serves nothing. SAFE, but see issue 006: the intact prior records are also blocked (no torn-tail truncation/recovery)."
fi
