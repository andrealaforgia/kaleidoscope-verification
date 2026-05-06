#!/usr/bin/env bash
# A15 — Bad config at startup → stderr `aperture: config error: ...`
# (pre-tracing direct write) and exit code 2. Source: ADR-0008
# Decision section ("Failure returns ApertureError::ConfigInvalid with
# a specific message; exit code 2; stderr `event=config_validation_failed`")
# and the source feed item A15.
#
# The runner runs aperture as a one-off container (NOT the compose
# stack's long-lived aperture-1) with a malformed TOML mounted at the
# expected path, captures stdout / stderr / exit code, and asserts.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

# Build a malformed config: the schema requires `bind_addr` to be a
# valid SocketAddr; pass a syntactically-broken value that will make
# figment / serde error out before any listener is bound.
MALFORMED_CONFIG="$EVIDENCE_DIR/malformed-aperture.toml"
cat > "$MALFORMED_CONFIG" <<'EOF'
[aperture.transport.grpc]
bind_addr = "this-is-not-a-valid-socket-addr"

[aperture.transport.http]
bind_addr = "0.0.0.0:4318"

[aperture.sink]
kind = "stub"
EOF
echo "wrote malformed config to ${MALFORMED_CONFIG}"

# Run aperture under the same image the compose stack uses. The
# compose-up'd aperture-1 keeps running on the side; we ignore it.
EXIT_CODE=0
docker run --rm \
    -v "${MALFORMED_CONFIG}:/etc/aperture/aperture.toml:ro" \
    kaleidoscope-expectations/aperture:under-test \
    --config /etc/aperture/aperture.toml \
    > "$EVIDENCE_DIR/aperture.oneshot.stdout.txt" \
    2> "$EVIDENCE_DIR/aperture.oneshot.stderr.txt" || EXIT_CODE=$?

echo "aperture one-shot exit code: ${EXIT_CODE}"
printf '%s\n' "$EXIT_CODE" > "$EVIDENCE_DIR/aperture.oneshot.exit-code.txt"

echo "stderr:"
cat "$EVIDENCE_DIR/aperture.oneshot.stderr.txt"

# Assertions:
# 1. exit code is 2 (config error pre-init).
# 2. stderr starts with the literal "aperture: config error: " prefix.
if [[ "$EXIT_CODE" != "2" ]]; then
    echo "expected exit code 2, got ${EXIT_CODE}" >&2
    exit 1
fi
if ! head -c 25 "$EVIDENCE_DIR/aperture.oneshot.stderr.txt" | grep -q "^aperture: config error: "; then
    echo "stderr does not start with 'aperture: config error: '" >&2
    exit 1
fi

echo "OK — bad config produced exit 2 with the expected stderr prefix"
