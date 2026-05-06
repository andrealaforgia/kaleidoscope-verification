#!/usr/bin/env bash
# A06 — OTLP/http metrics accepted.
# Thin wrapper over harness/assert-signal-acceptance.sh.
set -euo pipefail
EVIDENCE_DIR="$1"
exec "$HARNESS_DIR/assert-signal-acceptance.sh" \
    metrics http expectation-A06-pilot data_point_count "$EVIDENCE_DIR"
