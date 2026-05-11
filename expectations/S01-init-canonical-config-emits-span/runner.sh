#!/usr/bin/env bash
# S01 — `spark::init` with a canonical config returns
# `Ok(SparkGuard)`, and a span emitted via the global tracer arrives
# at aperture. Verified via the spark-consumer fixture running on
# the compose network and aperture's stderr `event=sink_accepted`.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SERVICE_NAME="expectation-S01-pilot"

# 1. Aperture readiness is gated centrally by run-expectation.sh.
# 2. Ensure spark-consumer image is built.
echo "step 1: ensure spark-consumer image is built"
( cd "$HARNESS_DIR" \
    && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

# 3. Run scenario on the compose network so it can reach aperture.
echo "step 2: run scenario s01-init-and-emit-trace"
docker run --rm --network "$COMPOSE_NETWORK" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s01-init-and-emit-trace \
    --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" \
    > "$EVIDENCE_DIR/consumer.stdout.txt" \
    2> "$EVIDENCE_DIR/consumer.stderr.txt"

echo "  consumer stdout:"
sed 's/^/    /' "$EVIDENCE_DIR/consumer.stdout.txt"

if ! grep -qE "^scenario=s01-init-and-emit-trace result=ok " "$EVIDENCE_DIR/consumer.stdout.txt"; then
    echo "consumer outcome line did not match expected pattern" >&2
    exit 1
fi

# 4. Allow forwarding flush.
sleep 2

# 5. Snapshot aperture stderr and look for the sink_accepted line.
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

echo "step 3: check aperture stderr for sink_accepted (signal=traces)"
ACCEPT_LINE=$(grep -F '"event":"sink_accepted"' "$EVIDENCE_DIR/aperture.live.stderr.txt" \
              | grep -F '"signal":"traces"' \
              | grep -F "\"resource.service.name\":\"${SERVICE_NAME}\"" \
              | tail -1 || true)
if [[ -z "$ACCEPT_LINE" ]]; then
    echo "no sink_accepted line for service ${SERVICE_NAME} in aperture stderr" >&2
    exit 1
fi
echo "  found: ${ACCEPT_LINE}"

echo "OK — spark::init Ok + span emitted via global tracer reached aperture for ${SERVICE_NAME}"
