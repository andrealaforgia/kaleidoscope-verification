#!/usr/bin/env bash
# L02 — `loom validate` exits 1 when at least one rule is broken.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
mkdir -p /tmp/fixture
cat > /tmp/fixture/good.toml <<TOML
[[rules]]
name = "good_rule"
query = "up == 0"
for_duration = "1m"
interval = "30s"
severity = "warning"

[[rules.sinks]]
kind = "webhook"
url = "https://ops.acme/alerts"
TOML
cat > /tmp/fixture/broken.toml <<TOML
[[rules]]
name = "broken_rule"
query = "up == 0"
for_duration = "not-a-duration"
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
"$HARNESS_DIR/run-loom.sh" "$EVIDENCE_DIR" L02 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/L02.stdout.txt" | tail -1 | cut -d= -f2)
echo "  loom validate exit: $EC"
if [[ "$EC" != "1" ]]; then echo "expected 1, got $EC" >&2; exit 1; fi
echo "OK — loom validate exited 1 on mixed valid + broken rules"
