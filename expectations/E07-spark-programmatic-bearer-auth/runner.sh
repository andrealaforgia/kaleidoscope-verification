#!/usr/bin/env bash
# E07 — the PROGRAMMATIC ingest-auth path: SparkConfig::with_bearer_token
# (spark-ingest-auth-v0, deliver 742536b) attaches `authorization: Bearer
# <token>` to all three OTLP exporters, so a code-configured (not env-
# configured) SDK user authenticates to aperture and round-trips to
# otelcol-sink. Complements E01-E04 (the OTEL_EXPORTER_OTLP_HEADERS env
# path). Covers the programmatic half of UC-AUTH-002 / the SDK auth knob.
#
# Positive: with --auth-token (a valid HS256 bearer) the span reaches the
# sink and aperture logs decision=allow. Negative control: WITHOUT a token
# the same emission is denied (no span at the sink), so the round-trip is
# the token's doing, not an open door.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${COMPOSE_NETWORK:?missing COMPOSE_NETWORK}"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
: "${CAPTURED_FILE:?missing CAPTURED_FILE}"

SERVICE_NAME="expectation-E07-pilot"

echo "step 1: build consumer (with the --auth-token / with_bearer_token arg)"
( cd "$HARNESS_DIR" && docker compose --profile fixture build spark-consumer ) \
    > "$EVIDENCE_DIR/spark-consumer-build.txt" 2>&1

JWT="$("$HARNESS_DIR/mint-ingest-jwt.sh")"

echo "step 2: NEGATIVE control — emit with NO token (expect denial, no span)"
: > "$CAPTURED_FILE"
docker run --rm --network "$COMPOSE_NETWORK" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s01-init-and-emit-trace --service-name "${SERVICE_NAME}-noauth" \
    --endpoint "http://aperture:4317" \
    > "$EVIDENCE_DIR/noauth.stdout.txt" 2> "$EVIDENCE_DIR/noauth.stderr.txt" || true
sleep 3
NOAUTH_SPAN=$(jq -r '.resourceSpans[]?.scopeSpans[]?.spans[]? | select(.name != null) | .name' "$CAPTURED_FILE" 2>/dev/null | head -1)
echo "noauth_span=[${NOAUTH_SPAN}]"

echo "step 3: POSITIVE — emit WITH the programmatic bearer (--auth-token)"
: > "$CAPTURED_FILE"
docker run --rm --network "$COMPOSE_NETWORK" \
    kaleidoscope-expectations/spark-consumer:under-test \
    --scenario s01-init-and-emit-trace --service-name "$SERVICE_NAME" \
    --endpoint "http://aperture:4317" --auth-token "$JWT" \
    > "$EVIDENCE_DIR/consumer.stdout.txt" 2> "$EVIDENCE_DIR/consumer.stderr.txt"
sleep 3
echo "  consumer outcome: $(cat "$EVIDENCE_DIR/consumer.stdout.txt")"
AUTH_SPAN=$(jq -r '.resourceSpans[]?.scopeSpans[]?.spans[]? | select(.name != null) | .name' "$CAPTURED_FILE" 2>/dev/null | head -1)
echo "auth_span=[${AUTH_SPAN}]"

( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true

# Positive: the programmatic bearer cleared aperture and the span landed.
[[ -n "$AUTH_SPAN" ]] || { echo "programmatic bearer did NOT round-trip (no span at sink)" >&2; tail -5 "$EVIDENCE_DIR/consumer.stderr.txt" >&2; exit 1; }
grep -F '"decision":"allow"' "$EVIDENCE_DIR/aperture.stderr.txt" | grep -qF 'ingest_traces' \
    || { echo "aperture did not log an allow for the authenticated ingest" >&2; exit 1; }
# Negative: without a token the same emission produced no span (denied).
[[ -z "$NOAUTH_SPAN" ]] || { echo "a span landed WITHOUT a token — auth not enforced on the programmatic path" >&2; exit 1; }
echo "OK — SparkConfig::with_bearer_token attaches the bearer: the authenticated span round-trips to otelcol-sink (aperture decision=allow); the same emission WITHOUT a token is denied (no span). The programmatic auth path works and is enforced."
