#!/usr/bin/env bash
# D16 — pulse SNAPSHOT ATOMICITY under a mid-snapshot process kill
# (black-box, on-disk). Per-store instance of the D09 pattern; see
# harness/assert-snapshot-atomicity.sh and D09's README for the full
# rationale. pulse-crash-target --seed-then-loop-snapshot seeds one
# acked datum, SIGKILLed mid-loop: canonical store.snapshot must be
# whole-or-absent (never torn) and the datum must survive in snapshot or
# WAL. Black-box ground for issue 007.
set -euo pipefail
: "${HARNESS_DIR:?missing HARNESS_DIR}"
exec "$HARNESS_DIR/assert-snapshot-atomicity.sh" "$1" D16 pulse pulse-crash-target
