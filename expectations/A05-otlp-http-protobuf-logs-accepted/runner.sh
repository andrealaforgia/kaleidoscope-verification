#!/usr/bin/env bash
# A05 — OTLP/http logs accepted.
# Thin wrapper over harness/assert-signal-acceptance.sh.
set -euo pipefail
EVIDENCE_DIR="$1"
exec "$HARNESS_DIR/assert-signal-acceptance.sh" \
    logs http expectation-A05-pilot record_count "$EVIDENCE_DIR"
