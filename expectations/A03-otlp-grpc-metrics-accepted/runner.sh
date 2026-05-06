#!/usr/bin/env bash
# A03 — OTLP/grpc metrics accepted.
# Thin wrapper over harness/assert-signal-acceptance.sh.
set -euo pipefail
EVIDENCE_DIR="$1"
exec "$HARNESS_DIR/assert-signal-acceptance.sh" \
    metrics grpc expectation-A03-pilot data_point_count "$EVIDENCE_DIR"
