#!/usr/bin/env bash
# assert-signal-acceptance.sh — shared driver for the A-prefix
# acceptance pilots (A01-A06).
#
# Drives telemetrygen against aperture for one (signal, transport)
# pair, then asserts aperture's stderr emitted exactly one
# `event=sink_accepted` line that matches the resource service.name
# and carries a positive count in the per-signal field
# (span_count / record_count / data_point_count).
#
# Args (all positional):
#   $1 signal           traces | logs | metrics
#   $2 transport        grpc | http
#   $3 service_name     resource attribute to tag and to grep for
#   $4 count_field      span_count | record_count | data_point_count
#   $5 evidence_dir     where to drop captures
#
# Env (set by harness/run-expectation.sh):
#   COMPOSE_NETWORK    docker compose network name
#   HARNESS_DIR        repo's harness/ dir (for `docker compose logs`)

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 <signal> <transport> <service_name> <count_field> <evidence_dir>" >&2
    exit 64
fi

SIGNAL="$1"
TRANSPORT="$2"
SERVICE_NAME="$3"
COUNT_FIELD="$4"
EVIDENCE_DIR="$5"

: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

TELEMETRYGEN_IMAGE="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"

case "$SIGNAL" in
    traces)  TELEMETRYGEN_COUNT_FLAG="--traces=1" ;;
    logs)    TELEMETRYGEN_COUNT_FLAG="--logs=1" ;;
    metrics) TELEMETRYGEN_COUNT_FLAG="--metrics=1" ;;
    *) echo "unknown signal '$SIGNAL'" >&2; exit 64 ;;
esac

case "$TRANSPORT" in
    grpc) TRANSPORT_FLAGS=(); ENDPOINT="aperture:4317" ;;
    http) TRANSPORT_FLAGS=("--otlp-http"); ENDPOINT="aperture:4318" ;;
    *) echo "unknown transport '$TRANSPORT'" >&2; exit 64 ;;
esac
# `set -u` (nounset) treats `"${TRANSPORT_FLAGS[@]}"` as unbound when
# the array is empty (the gRPC case). The standard guard is the
# `${name[@]+...}` parameter expansion: it expands to nothing if the
# array is empty/unset, otherwise to the requested expansion.

# 1. Wait for aperture readiness.
echo "step 1: waiting for aperture /readyz to return 200"
DEADLINE=$(( SECONDS + 30 ))
while (( SECONDS < DEADLINE )); do
    code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' \
                 http://localhost:4318/readyz 2>/dev/null || echo "")"
    if [[ "$code" == "200" ]]; then
        echo "  aperture ready"
        break
    fi
    sleep 1
done
if [[ "${code:-}" != "200" ]]; then
    echo "aperture never became ready" >&2
    exit 1
fi

# 2. Send one signal payload. Mandatory ingest auth (N29): attach a
#    valid HS256 bearer or aperture 401s before the body is parsed.
JWT="$("$HARNESS_DIR/mint-ingest-jwt.sh")"
echo "step 2: sending one ${SIGNAL} payload via telemetrygen (${TRANSPORT}, authenticated)"
docker run --rm --network "$COMPOSE_NETWORK" \
    "$TELEMETRYGEN_IMAGE" \
    "$SIGNAL" \
        ${TRANSPORT_FLAGS[@]+"${TRANSPORT_FLAGS[@]}"} \
        --otlp-endpoint="$ENDPOINT" \
        --otlp-insecure \
        --otlp-header "authorization=\"Bearer ${JWT}\"" \
        "$TELEMETRYGEN_COUNT_FLAG" \
        --otlp-attributes "service.name=\"${SERVICE_NAME}\"" \
    > "$EVIDENCE_DIR/telemetrygen.stdout.txt" \
    2> "$EVIDENCE_DIR/telemetrygen.stderr.txt"
echo "  telemetrygen exited 0"

# 3. Snapshot aperture stderr live.
sleep 1
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

# 4. Assert sink_accepted line for this signal + service.
echo "step 3: checking aperture stderr for sink_accepted (signal=${SIGNAL})"
ACCEPT_LINE="$(grep -F '"event":"sink_accepted"' "$EVIDENCE_DIR/aperture.live.stderr.txt" \
                 | grep -F "\"signal\":\"${SIGNAL}\"" \
                 | grep -F "\"resource.service.name\":\"${SERVICE_NAME}\"" || true)"

if [[ -z "$ACCEPT_LINE" ]]; then
    echo "no sink_accepted line for signal=${SIGNAL} service=${SERVICE_NAME}" >&2
    exit 1
fi
echo "  found: ${ACCEPT_LINE}"

# 5. Extract the per-signal count and assert > 0.
OBSERVED_COUNT="$(printf '%s' "$ACCEPT_LINE" \
                   | sed -n "s/.*\"${COUNT_FIELD}\":\\([0-9]*\\).*/\\1/p")"
if [[ -z "$OBSERVED_COUNT" ]]; then
    echo "could not extract ${COUNT_FIELD} from sink_accepted line" >&2
    exit 1
fi
echo "  observed ${COUNT_FIELD}=${OBSERVED_COUNT}"
if (( OBSERVED_COUNT <= 0 )); then
    echo "${COUNT_FIELD} must be > 0; got ${OBSERVED_COUNT}" >&2
    exit 1
fi

echo "OK — aperture acked ${SIGNAL} on ${TRANSPORT} with ${COUNT_FIELD}=${OBSERVED_COUNT} for service ${SERVICE_NAME}"
