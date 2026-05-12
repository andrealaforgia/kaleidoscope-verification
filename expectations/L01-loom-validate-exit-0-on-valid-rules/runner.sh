#!/usr/bin/env bash
# L01 — `loom validate --rules <DIR>` exits 0 when every TOML rule loads.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
mkdir -p /tmp/fixture
cat > /tmp/fixture/rule.toml <<TOML
[[rules]]
name = "service_down"
query = "up == 0"
for_duration = "1m"
interval = "30s"
severity = "warning"

[[rules.sinks]]
kind = "webhook"
url = "https://ops.acme/alerts"
TOML
EC=0
$LOOM validate --rules /tmp/fixture || EC=$?
echo "exit=$EC"
'
"$HARNESS_DIR/run-loom.sh" "$EVIDENCE_DIR" L01 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/L01.stdout.txt" | tail -1 | cut -d= -f2)
echo "  loom validate exit: $EC"
if [[ "$EC" != "0" ]]; then echo "expected 0, got $EC" >&2; exit 1; fi
echo "OK — loom validate exited 0 on valid rules"
