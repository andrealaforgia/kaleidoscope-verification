#!/usr/bin/env bash
# D14 — beacon WAL-fsync REFUSAL on a lying substrate (black-box).
# Per-store instance of the D08 pattern (see
# harness/assert-probe-lying-refusal.sh and D08's README for the full
# rationale). beacon-crash-target --probe-lying must refuse a lying
# fsync substrate: event=health.startup.refused substrate=<descriptor>,
# non-zero exit, no store payload written (refuse before open).
set -euo pipefail
: "${HARNESS_DIR:?missing HARNESS_DIR}"
exec "$HARNESS_DIR/assert-probe-lying-refusal.sh" "$1" D14 beacon beacon-crash-target
