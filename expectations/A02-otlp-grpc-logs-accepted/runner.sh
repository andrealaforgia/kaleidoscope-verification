#!/usr/bin/env bash
# A02 — OTLP/grpc logs accepted.
# Thin wrapper over harness/assert-signal-acceptance.sh.
set -euo pipefail
EVIDENCE_DIR="$1"
exec "$HARNESS_DIR/assert-signal-acceptance.sh" \
    logs grpc expectation-A02-pilot record_count "$EVIDENCE_DIR"
