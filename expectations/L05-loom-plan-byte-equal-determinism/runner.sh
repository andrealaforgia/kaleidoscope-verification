#!/usr/bin/env bash
# L05 — `loom plan --from <src> --to <dest>` produces byte-equal
# output on repeated invocations against the same input pair
# (KPI 2 determinism).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
mkdir -p /tmp/src /tmp/dest
cat > /tmp/src/rule.toml <<TOML
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
$LOOM plan --from /tmp/src --to /tmp/dest > /tmp/plan1.out 2>&1
$LOOM plan --from /tmp/src --to /tmp/dest > /tmp/plan2.out 2>&1
echo "---plan1 head---"
head -10 /tmp/plan1.out
if cmp -s /tmp/plan1.out /tmp/plan2.out; then
    echo "byte-equal=true"
else
    echo "byte-equal=false"
    diff /tmp/plan1.out /tmp/plan2.out | head -20
fi
'
"$HARNESS_DIR/run-loom.sh" "$EVIDENCE_DIR" L05 "$INLINE"

if ! grep -q "byte-equal=true" "$EVIDENCE_DIR/L05.stdout.txt"; then
    echo "plan output not byte-equal across runs" >&2
    exit 1
fi
echo "OK — loom plan output is byte-equal across two consecutive runs"
